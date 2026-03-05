# 🚀 Quick Start Guide

## Installation en 30 secondes

```bash
# 1. Clone le repo (après avoir pushé)
git clone https://github.com/decarvalhoe/universal-project-launcher.git
cd universal-project-launcher

# 2. Installe les dépendances minimales
pip install PyYAML python-dotenv

# 3. Lance une session 42-training
python3 src/context_generator.py profiles/42-training.yaml
```

## Utilisation Windows (le plus simple)

1. **Double-clic** sur `examples/LAUNCH_42_CLAUDE.bat`
2. **C'est tout !** Le contexte est généré et la session démarre

## Créer un nouveau projet

```bash
python3 src/add_project.py
# Suis l'assistant interactif
```

## Structure des fichiers

```
📁 universal-project-launcher/
  📄 README.md           # Documentation complète
  📄 QUICK_START.md      # Ce fichier (démarrage rapide)
  📁 src/                # Code source
    ⚙️ launcher.py       # Launcher principal
    ⚙️ context_generator.py # Générateur de contexte
    ⚙️ add_project.py    # Assistant nouveaux projets
  📁 profiles/           # Profils de projets
    📄 42-training.yaml  # Profil pour Piscine 42
  📁 examples/           # Exemples de launchers
    🚀 LAUNCH_42_CLAUDE.bat # Launcher Windows 42
```

## Commandes utiles

### Générer un contexte
```bash
python3 src/context_generator.py profiles/YOUR_PROJECT.yaml
```

### Créer un nouveau profil
```bash
python3 src/add_project.py
```

### Voir les statistiques du contexte
```bash
# Le générateur affiche automatiquement :
# - Nombre de lignes
# - Nombre de caractères
# - Tokens approximatifs
# - Économies réalisées
```

## Support

- 🐛 Issues : https://github.com/decarvalhoe/universal-project-launcher/issues
- 📖 Documentation : docs/README_UNIVERSAL_LAUNCHER.md
- 💡 Exemples : profiles/42-training.yaml

## Tips

1. **Pour 42** : Le profil suit automatiquement ta progression
2. **Pour dev** : Ajoute tes fichiers importants dans `context_files`
3. **Économie** : ~70% de réduction des tokens vs contexte manuel
4. **Cache** : Les fichiers non modifiés ne sont pas rechargés

---

**Créé par Eric de Carvalho** pour la préparation Piscine 42 Lausanne 2026