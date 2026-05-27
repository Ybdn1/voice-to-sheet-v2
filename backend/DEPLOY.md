## Objectif

Faire tourner le backend VoiceToSheet sur un serveur toujours allume, pour que
l'APK fonctionne sur les telephones des collegues sans dependre du PC local.

## Option recommandee

Le plus simple ici est de deployer le backend sur Render avec le fichier
`render.yaml` ajoute a la racine du projet.

## Ce qu'il faut heberger

Le backend FastAPI seulement.

Le frontend mobile Flutter continuera d'etre compile en APK, mais il devra
pointer vers une URL publique, par exemple:

`https://api.ton-domaine.com`

## Variables d'environnement cote serveur

Definir au minimum:

- `MISTRAL_API_KEY`
- `MISTRAL_MODEL` (optionnel, valeur par defaut: `mistral-large-latest`)
- `VOICE_TO_SHEET_USERS` (optionnel, ex: `agent1:mdp1,agent2:mdp2`)

Si tu heberges aussi une version web:

- `VOICE_TO_SHEET_CORS_ORIGINS`

Exemple:

```env
MISTRAL_API_KEY=replace_me
MISTRAL_MODEL=mistral-large-latest
VOICE_TO_SHEET_USERS=agent.demo:demo1234
VOICE_TO_SHEET_CORS_ORIGINS=https://app.ton-domaine.com
```

## Deployer sur Render

1. Pousse le projet sur GitHub.
2. Cree un compte Render puis ouvre `New > Blueprint`.
3. Selectionne le repo.
4. Render detectera `render.yaml` a la racine.
5. Fournis les secrets demandes:
   - `MISTRAL_API_KEY`
   - `VOICE_TO_SHEET_USERS`
6. Lance le deploy.
7. Quand le service est pret, recupere son URL publique, par exemple:
   `https://voice-to-sheet-backend.onrender.com`

Le fichier `render.yaml` est configure pour:

- deployer uniquement le dossier `backend`
- utiliser le `Dockerfile` du backend
- verifier l'etat du service via `/health`
- demander les secrets sensibles dans Render

Important:

- le plan `starter` est prevu pour un backend toujours actif
- si tu passes en `free`, le service pourra se mettre en veille

## Lancer localement

```powershell
cd backend
venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

## Construire un conteneur Docker

```powershell
cd backend
docker build -t voice-to-sheet-backend .
docker run -p 8000:8000 --env-file .env voice-to-sheet-backend
```

## Construire l'APK pour la production

Depuis `frontend`, compiler l'application avec l'URL publique du backend:

```powershell
flutter build apk --release --dart-define=VOICE_TO_SHEET_API_URL=https://api.ton-domaine.com
```

Ou plus simplement sous Windows:

```powershell
build_prod_apk.bat https://api.ton-domaine.com
```

## Verification minimale

Une fois le backend deploye, verifier:

```text
GET https://api.ton-domaine.com/health
```

La reponse attendue est:

```json
{"status":"ok"}
```
