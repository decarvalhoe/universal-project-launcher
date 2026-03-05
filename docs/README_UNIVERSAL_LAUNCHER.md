# 🚀 Universal Project Launcher

## Système de lancement optimisé pour sessions Claude

### 📋 Vue d'ensemble

Le **Universal Project Launcher** est un système centralisé pour gérer et lancer des sessions Claude optimisées avec contexte pré-chargé. Conçu pour minimiser les coûts en tokens et maximiser l'efficacité.

### ✨ Fonctionnalités

- ✅ **Profils multi-projets** : Support de différents types (development, learning, devops, research)
- ✅ **Contexte optimisé** : Génération automatique de contexte minimal mais complet
- ✅ **Cache intelligent** : Évite de recharger les fichiers non modifiés
- ✅ **Launcher Windows** : Interface système tray + launchers .bat one-click
- ✅ **Templates** : Création rapide de nouveaux profils
- ✅ **Historique** : Tracking des sessions et statistiques d'usage

### 📁 Structure

```
~/.agent-conductor/
├── profiles/                # Profils de projets
│   ├── 42-training.yaml    # Profil pour la préparation 42
│   └── *.yaml              # Autres profils
├── contexts/               # Contextes générés
│   └── *_context.md       # Fichiers de contexte optimisés
├── templates/             # Templates pour nouveaux projets
│   └── project_template.yaml
├── universal-project-launcher.py  # Launcher principal
├── context_generator.py           # Générateur de contexte
└── add_project.py                # Assistant création de profils
```

### 🎯 Utilisation

#### 1. Lancer une session 42-training (Windows)

**Option A : Double-clic sur le .bat**
```batch
~/42_training/LAUNCH_42_CLAUDE.bat
```

**Option B : Depuis WSL**
```bash
cd ~/.agent-conductor
python3 context_generator.py profiles/42-training.yaml
cd ~/42_training
claude --context ~/.agent-conductor/contexts/42-training_context.md
```

#### 2. Créer un nouveau projet

```bash
python3 ~/.agent-conductor/add_project.py
```

Suit l'assistant interactif pour configurer :
- ID et nom du projet
- Type (development, learning, etc.)
- Chemin et description
- Rôle de Claude
- Fichiers de contexte

#### 3. Générer manuellement un contexte

```bash
python3 ~/.agent-conductor/context_generator.py profiles/YOUR_PROJECT.yaml
```

### 🔧 Configuration d'un profil

Exemple de profil optimisé (`42-training.yaml`) :

```yaml
id: "42-training"
name: "42 Training - Piscine Preparation"
type: "learning"
path: "/home/decarvalhoe/42_training"

claude_context:
  role: |
    Assistant d'apprentissage pour la Piscine 42
  learning_mode: |
    Guide étape par étape avec feedback
  current_level: |
    Exercice 2 - Manipulation fichiers

context_files:
  - "REPRENDRE_SESSION.md"
  - "progression.json"

quick_commands:
  - name: "Status"
    command: "cat progression.json | jq '.progress'"
```

### 💡 Optimisation des tokens

Le système optimise automatiquement :

1. **Cache de fichiers** : Hash MD5 pour détecter les changements
2. **Compression** : Suppression des espaces/lignes vides excessifs
3. **Truncation** : Limite à 10000 caractères par défaut
4. **Sélection intelligente** : Inclut seulement les infos pertinentes

### 📊 Résultats typiques

- **Contexte 42-training** : ~960 tokens (au lieu de 3000+)
- **Temps de génération** : < 1 seconde
- **Économies** : ~70% de réduction des tokens

### 🚀 Lancement rapide par type

#### Projets d'apprentissage (comme 42)
```batch
:: Focus sur progression et erreurs
:: Contexte minimal mais avec historique
LAUNCH_42_CLAUDE.bat
```

#### Projets de développement
```batch
:: Focus sur git status et architecture
:: Inclut README et configs
launch_my_project.bat
```

#### Projets DevOps
```batch
:: Focus sur docker et logs
:: Inclut compose files et envs
launch_devops.bat
```

### 🎓 Cas d'usage : 42 Training

Le profil `42-training` est spécialement optimisé pour :

1. **Apprentissage progressif** : Suit ta progression exercice par exercice
2. **Mémorisation des erreurs** : Rappelle tes erreurs pour apprendre
3. **Mode strict** : Pas d'IA pendant les vrais exercices
4. **Muscle memory** : Focus sur la répétition et pratique

### 📈 Évolutions futures

- [ ] Interface GUI complète (Tkinter)
- [ ] Sync multi-machines via Git
- [ ] Intégration Claude CLI native
- [ ] Métriques détaillées par session
- [ ] Profils partagés (marketplace)

### 🐛 Troubleshooting

**Le contexte ne se génère pas**
- Vérifier que le profil existe : `ls ~/.agent-conductor/profiles/`
- Vérifier les permissions : `chmod +x ~/.agent-conductor/*.py`

**Le launcher Windows ne marche pas**
- Vérifier que WSL est installé
- Vérifier les chemins dans le .bat

**Contexte trop gros**
- Réduire les `context_files`
- Ajuster `max_context_size` dans `context_generator.py`

### 📝 Notes

- Les profils sont en YAML pour faciliter l'édition manuelle
- Les contextes sont en Markdown pour la lisibilité
- Le cache est en mémoire (pas persistant entre sessions)
- Les stats sont en SQLite pour la performance

---

**Author**: Eric de Carvalho
**Version**: 3.0
**Date**: 2026-03-05
**License**: MIT