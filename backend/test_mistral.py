import os
from pathlib import Path

from dotenv import load_dotenv
from mistralai.client import Mistral


BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

api_key = os.getenv("MISTRAL_API_KEY")

if not api_key:
    raise ValueError("MISTRAL_API_KEY non trouvee dans backend/.env")

client = Mistral(api_key=api_key)

prompt = (
    "Ecris uniquement un JSON valide sous forme de liste avec "
    "site='La Valette', zone='Boue', equipement='Pompe 1', "
    "description='cassee'."
)

response = client.chat.complete(
    model="mistral-large-latest",
    messages=[
        {
            "role": "system",
            "content": "Tu retournes uniquement du JSON valide.",
        },
        {"role": "user", "content": prompt},
    ],
    temperature=0,
)

print(response.choices[0].message.content)
