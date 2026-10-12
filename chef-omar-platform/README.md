# Chef Omar — plateforme v2 (site + console chef/admin + Supabase + Netlify)

## Fichiers
| Fichier | Rôle |
|---|---|
| `index.html` | Site visiteur : Chef, Réels & stories, Plats 360°, Calendrier (ticket), Réserver, Livre d'Or public, Masterclasses & paiement, À propos, Conditions, Mon espace, 3 thèmes |
| `editeur.html` | Console privée (chef et admin, rubriques selon le rôle) |
| `config.js` | URL + clé publique « anon » Supabase |
| `supabase/schema.sql` | Tables, rôles, règles de sécurité, fonctions, cloud (3 espaces de stockage) |
| `netlify/functions/inscription.js` | Reçoit la capture de paiement, la range dans le cloud privé, l'enregistre, alerte Telegram |
| `netlify.toml`, `.env.example`, `.gitignore` | Déploiement et secrets |

## Qui peut quoi
| | Chef (Omarngalladiop604@gmail.com) | Admin (bruthesyoulou@gmail.com) |
|---|---|---|
| Profil, photo, contact & réseaux, plats 360°, formules, masterclasses | Modifie | Voit (journaux) |
| Calendrier, inscrits, annulation, messages aux visiteurs | Gère | Voit |
| Réels & stories (image, vidéo 30 s, texte) | Publie | Publie |
| Paiements : voir la capture, valider, annuler, contacter | Oui | Voit seulement |
| Leçons (cloud privé) + liens d'envoi | Oui | Non |
| Numéros de paiement, marque, fonction d'inscription, options, textes légaux | Non | Oui |
| Annonces pour tous (image, vidéo 30 s, texte) | Non | Oui |
| Tableau de bord, finances, journaux (audit, transactions, visiteurs), exports, mises à jour | Non | Oui |

Ces limites sont appliquées par la base (règles RLS), pas seulement par l'interface.

## 1. Supabase
1. Créez le projet. **Authentication > Providers > Email : désactivez « Allow new users to sign up »**.
2. **Authentication > Users > Add user** : créez les deux comptes (admin et chef) avec ces emails exacts et un mot de passe fort chacun.
3. Si la base contient d'anciennes tables : supprimez-les d'abord (voir plus bas), puis collez `supabase/schema.sql` dans **SQL Editor > Run**. Les espaces `media` (public), `recus` et `lecons` (privés) sont créés automatiquement.
4. **Project Settings > API** : copiez *Project URL* et la clé *anon public* dans `config.js`. La clé *service_role* va seulement dans Netlify.

## 2. GitHub
Dépôt **privé et vide** sur github.com, puis dans ce dossier :
```bash
git init
git add .
git commit -m "Chef Omar platform v2"
git branch -M main
git remote add origin https://github.com/VOTRE_COMPTE/chef-omar-platform.git
git push -u origin main
```
## 3. Netlify
Importez le dépôt (dossier publié `.`, pas de commande de build). Ajoutez les variables de `.env.example` (au minimum `SUPABASE_URL` et `SUPABASE_SERVICE_KEY`), puis relancez un déploiement.

## 4. Utilisation
- Console : `https://VOTRE-SITE.netlify.app/editeur.html`.
- Paiement : le visiteur envoie sa capture → elle apparaît dans « Paiements » (et sur Telegram si configuré) → le chef valide ou annule → le visiteur reçoit un message dans « Mon espace » → le chef crée un lien privé de 7 jours dans « Leçons » et l'envoie par WhatsApp, Telegram ou dans l'espace du visiteur.
- Calendrier : le visiteur confirme sa place (nom + numéro privé) et reçoit un ticket à copier, télécharger ou capturer ; tout est visible dans « Calendrier & inscrits » et dans les journaux.


## Clés, fichier `.env` et Telegram
**Deux clés Supabase, deux usages :**
- `sb_publishable_…` : publique, dans `config.js` (déjà renseignée), peut aller sur GitHub.
- `sb_secret_…` : secrète, uniquement dans `.env` (local) et dans les variables Netlify. Si elle a été partagée par erreur, créez-en une nouvelle (Supabase > Settings > API Keys), supprimez l'ancienne, puis mettez à jour `.env` et Netlify.

**Le fichier `.env`** se place à la racine du projet. Il est ignoré par Git (`.gitignore`). Il ne sert qu'en local : `npm i -g netlify-cli`, puis `netlify dev` lance le site et la fonction avec ces valeurs. En ligne, Netlify ne lit pas ce fichier : envoyez-le avec `netlify login`, `netlify link`, puis `netlify env:import .env`, ou saisissez les variables dans Site configuration > Environment variables, puis redéployez.

**Telegram (capture de paiement sur le téléphone du chef) :**
1. Dans Telegram, ouvrez **@BotFather**, envoyez `/newbot`, choisissez un nom et un identifiant finissant par `bot`. BotFather donne le **token** (`123456:ABC…`).
2. Ouvrez votre nouveau bot et envoyez-lui « Bonjour » (un bot ne peut pas écrire en premier).
3. Dans votre navigateur, ouvrez `https://api.telegram.org/bot<TOKEN>/getUpdates` (en remplaçant `<TOKEN>`). Repérez `"chat":{"id":123456789` : c'est le **TELEGRAM_CHAT_ID**. Pour un groupe, ajoutez le bot au groupe, écrivez-y, et l'id commence par `-`.
4. Renseignez `TELEGRAM_BOT_TOKEN` et `TELEGRAM_CHAT_ID` dans `.env` et dans Netlify, puis redéployez.
5. Test : envoyez un faux reçu depuis le site ; la photo arrive sur Telegram avec la référence, le montant et le contact, et la ligne apparaît dans « Paiements ».

**WhatsApp :** l'envoi automatique d'une capture vers WhatsApp passe par l'API WhatsApp Business de Meta (numéro dédié, compte vérifié, modèles de message approuvés). Elle n'est pas incluse. Les captures restent visibles dans la console, et Telegram sert d'alerte.

## Supprimer d'anciennes tables avant d'installer
```sql
do $$ declare r record; begin
  for r in (select tablename from pg_tables where schemaname='public') loop
    execute format('drop table if exists public.%I cascade', r.tablename); end loop; end $$;
```
(Supprime définitivement toutes les tables du schéma `public`.)

## Limites connues
- Les notifications fonctionnent quand le site est ouvert (pas de notification push site fermé).
- WhatsApp, Telegram et email : la console ouvre un message prérempli que le chef envoie lui-même ; il n'y a pas d'envoi automatique.
- Les textes « Conditions d'utilisation » sont un modèle à faire relire avant publication.
- Pas de limite de débit sur l'envoi de reçus ni sur les avis (un délai d'une minute côté navigateur seulement).
