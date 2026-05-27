import json
import re

from fastapi import HTTPException

from app.config import MISTRAL_API_KEY, MISTRAL_MODEL
from app.schemas.report import DescriptionRequest, EquipmentRow

try:
    from mistralai.client import Mistral
except ImportError:
    Mistral = None


class AIExtractorService:
    def __init__(self) -> None:
        self._client = Mistral(api_key=MISTRAL_API_KEY) if Mistral and MISTRAL_API_KEY else None

    def _build_prompt(self, data: DescriptionRequest) -> str:
        return f"""
Tu es un moteur d'extraction d'equipements industriels pour l'application VoiceToSheet.

Objectif :
- Lire une description vocale libre d'un agent de terrain.
- Extraire tous les equipements mentionnes.
- Retourner uniquement un tableau JSON valide.

Contraintes strictes :
1. Retourne uniquement un tableau JSON, sans phrase d'introduction, sans explication, sans markdown.
2. Chaque equipement mentionne doit apparaitre dans le resultat.
3. Si une quantite est mentionnee, cree une ligne par element.
4. Si un parent contient des enfants, le nom de l'enfant doit inclure le parent.
5. Si le parent est explicitement mentionne, retourne aussi sa propre ligne.
6. Le champ "description" doit contenir uniquement l'etat ou la caracteristique technique utile.
7. Si aucune description utile n'est mentionnee, retourne une chaine vide.
8. N'invente pas d'equipement absent du texte.
9. Conserve exactement les valeurs suivantes :
   - site = "{data.site}"
   - contrat = "{data.contrat}"
   - zone = "{data.zone}"

Structure obligatoire :
[
  {{
    "site": "{data.site}",
    "contrat": "{data.contrat}",
    "zone": "{data.zone}",
    "equipement": "Nom equipement",
    "description": "Etat ou caracteristique"
  }}
]

Exemple :
[
  {{
    "site": "La Valette",
    "contrat": "Exploitation",
    "zone": "Boue",
    "equipement": "Reservoir eaux brutes",
    "description": ""
  }},
  {{
    "site": "La Valette",
    "contrat": "Exploitation",
    "zone": "Boue",
    "equipement": "Pompe 1 Reservoir eaux brutes",
    "description": "cassee"
  }},
  {{
    "site": "La Valette",
    "contrat": "Exploitation",
    "zone": "Boue",
    "equipement": "Pompe 2 Reservoir eaux brutes",
    "description": "50DN"
  }},
  {{
    "site": "La Valette",
    "contrat": "Exploitation",
    "zone": "Boue",
    "equipement": "Lit 1 eaux traitees",
    "description": ""
  }},
  {{
    "site": "La Valette",
    "contrat": "Exploitation",
    "zone": "Boue",
    "equipement": "Cheminee 1 Lit 1 eaux traitees",
    "description": ""
  }}
]

Description agent :
\"\"\"{data.description}\"\"\"
""".strip()

    def _strip_code_fences(self, text: str) -> str:
        cleaned = text.strip()
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)
        return cleaned.strip()

    def _extract_json_array(self, text: str) -> str:
        cleaned = self._strip_code_fences(text)
        if cleaned.startswith("[") and cleaned.endswith("]"):
            return cleaned

        start = cleaned.find("[")
        end = cleaned.rfind("]")
        if start == -1 or end == -1 or end <= start:
            raise ValueError("Aucun tableau JSON detecte dans la reponse du modele.")

        return cleaned[start : end + 1]

    def _normalize_rows(
        self,
        raw_rows: list[dict],
        data: DescriptionRequest,
    ) -> list[EquipmentRow]:
        rows: list[EquipmentRow] = []

        for index, item in enumerate(raw_rows, start=1):
            if not isinstance(item, dict):
                raise ValueError(f"La ligne {index} n'est pas un objet JSON.")

            equipement = str(item.get("equipement", "")).strip()
            description = str(item.get("description", "")).strip()

            if not equipement:
                raise ValueError(f"La ligne {index} ne contient pas de champ 'equipement'.")

            rows.append(
                EquipmentRow(
                    site=data.site,
                    contrat=data.contrat,
                    zone=data.zone,
                    equipement=equipement,
                    description=description,
                )
            )

        if not rows:
            raise ValueError("Le modele a retourne une liste vide.")

        return rows

    def extract_rows(self, data: DescriptionRequest) -> tuple[list[EquipmentRow], str]:
        if Mistral is None:
            raise HTTPException(
                status_code=500,
                detail="Le package mistralai n'est pas installe dans cet environnement Python.",
            )

        if self._client is None:
            raise HTTPException(
                status_code=500,
                detail="MISTRAL_API_KEY manquante dans le fichier .env.",
            )

        response = self._client.chat.complete(
            model=MISTRAL_MODEL,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Tu extrais des equipements industriels et tu reponds "
                        "uniquement avec un tableau JSON valide."
                    ),
                },
                {"role": "user", "content": self._build_prompt(data)},
            ],
            temperature=0,
        )

        raw_content = response.choices[0].message.content or ""
        payload = self._extract_json_array(raw_content)
        parsed = json.loads(payload)

        if not isinstance(parsed, list):
            raise ValueError("Le modele n'a pas retourne une liste JSON.")

        return self._normalize_rows(parsed, data), raw_content


ai_extractor_service = AIExtractorService()
