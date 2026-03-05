#!/usr/bin/env python3
"""
Add New Project Profile
========================
Assistant interactif pour créer rapidement de nouveaux profils de projet.
"""

import os
import sys
import yaml
import shutil
from pathlib import Path
from datetime import datetime

# Paths
CONFIG_DIR = Path.home() / ".agent-conductor"
PROFILES_DIR = CONFIG_DIR / "profiles"
TEMPLATES_DIR = CONFIG_DIR / "templates"

def create_project_profile():
    """Créer interactivement un nouveau profil de projet"""

    print("""
╔════════════════════════════════════════╗
║   📁 CREATION DE NOUVEAU PROFIL        ║
╚════════════════════════════════════════╝
""")

    # Demander les informations de base
    project_id = input("🆔 ID du projet (ex: my-api): ").strip()
    if not project_id:
        print("❌ ID requis!")
        return

    project_name = input("📝 Nom du projet (ex: My Awesome API): ").strip()
    if not project_name:
        project_name = project_id.replace("-", " ").title()

    # Type de projet
    print("\n📚 Types de projet disponibles:")
    print("1. development - Projet de développement")
    print("2. learning - Session d'apprentissage")
    print("3. devops - Infrastructure/DevOps")
    print("4. research - Recherche/Expérimentation")
    print("5. custom - Personnalisé")

    project_type = input("\nChoisir le type (1-5): ").strip()
    type_map = {
        "1": "development",
        "2": "learning",
        "3": "devops",
        "4": "research",
        "5": "custom"
    }
    project_type = type_map.get(project_type, "custom")

    # Chemin du projet
    default_path = Path.home() / "projects" / project_id
    project_path = input(f"\n📂 Chemin du projet [{default_path}]: ").strip()
    if not project_path:
        project_path = str(default_path)

    # Description
    description = input("\n📄 Description courte: ").strip()

    # Créer le profil depuis le template
    template_file = TEMPLATES_DIR / "project_template.yaml"
    profile_file = PROFILES_DIR / f"{project_id}.yaml"

    if profile_file.exists():
        overwrite = input(f"\n⚠️ Le profil {project_id} existe déjà. Écraser? (y/N): ")
        if overwrite.lower() != 'y':
            print("❌ Annulé")
            return

    # Charger le template
    with open(template_file, 'r', encoding='utf-8') as f:
        profile = yaml.safe_load(f)

    # Personnaliser le profil
    profile['id'] = project_id
    profile['name'] = project_name
    profile['type'] = project_type
    profile['path'] = project_path
    profile['description'] = description
    profile['created_at'] = datetime.now().isoformat()
    profile['session_name'] = f"{project_id}-claude"

    # Demander le rôle Claude
    print("\n🤖 Définir le rôle de Claude pour ce projet:")
    claude_role = input("Rôle (ex: Assistant développement API REST): ").strip()
    if claude_role:
        profile['claude_context']['role'] = claude_role

    # Demander si on veut des fichiers de contexte spécifiques
    print("\n📁 Fichiers à inclure dans le contexte (séparés par des virgules):")
    print("Exemples: README.md, package.json, docker-compose.yml")
    context_files = input("Fichiers: ").strip()
    if context_files:
        profile['context_files'] = [f.strip() for f in context_files.split(',')]

    # Sauvegarder le profil
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    with open(profile_file, 'w', encoding='utf-8') as f:
        yaml.dump(profile, f, default_flow_style=False, allow_unicode=True)

    print(f"""
✅ Profil créé avec succès!

📋 Résumé:
- ID: {project_id}
- Type: {project_type}
- Fichier: {profile_file}

🚀 Pour lancer:
1. Windows: Créer un raccourci vers launch_project.bat
2. Linux: python3 ~/.agent-conductor/universal-project-launcher.py

💡 Pour personnaliser davantage:
- Éditer: {profile_file}
- Ajouter des commandes rapides
- Configurer les variables d'environnement
""")

    # Proposer de créer un launcher batch Windows
    if sys.platform == "win32" or input("\nCréer un launcher Windows .bat? (y/N): ").lower() == 'y':
        create_windows_launcher(project_id, project_name, project_path)

def create_windows_launcher(project_id: str, project_name: str, project_path: str):
    """Créer un fichier .bat pour Windows"""
    launcher_content = f"""@echo off
:: ========================================
:: {project_name} - Claude Session Launcher
:: Generated: {datetime.now().strftime('%Y-%m-%d')}
:: ========================================

title {project_name} - Claude Session
color 0A

echo ========================================
echo    {project_name.upper()}
echo    Claude Optimized Session
echo ========================================
echo.

:: Generate optimized context
echo [1/3] Generating optimized context...
wsl.exe -e bash -c "cd ~/.agent-conductor && python3 context_generator.py profiles/{project_id}.yaml"

:: Show project status
echo.
echo [2/3] Project status...
wsl.exe -e bash -c "cd {project_path} && pwd && ls -la | head -5"

:: Launch session
echo.
echo [3/3] Launching Claude session...
wsl.exe -e bash -c "cd {project_path} && echo 'Context ready at: ~/.agent-conductor/contexts/{project_id}_context.md' && exec bash"

pause
"""

    launcher_file = Path.home() / f"launch_{project_id}.bat"
    with open(launcher_file, 'w') as f:
        f.write(launcher_content)

    print(f"✅ Launcher Windows créé: {launcher_file}")

if __name__ == "__main__":
    try:
        create_project_profile()
    except KeyboardInterrupt:
        print("\n\n❌ Annulé par l'utilisateur")
    except Exception as e:
        print(f"\n❌ Erreur: {e}")