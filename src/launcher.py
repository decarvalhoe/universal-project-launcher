#!/usr/bin/env python3
"""
Universal Project Launcher with Claude Context Optimization
============================================================
Système unifié pour lancer des sessions Claude optimisées par projet
avec contexte pré-chargé et persistance intelligente.

Author: Eric de Carvalho
Version: 3.0
Date: 2026-03-05
"""

import os
import sys
import json
import yaml
import sqlite3
import subprocess
import webbrowser
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field, asdict
from enum import Enum
import tkinter as tk
from tkinter import ttk, messagebox
import pystray
from PIL import Image, ImageDraw
import threading
import time

# Configuration paths
CONFIG_DIR = Path.home() / ".agent-conductor"
PROFILES_DIR = CONFIG_DIR / "profiles"
CONTEXTS_DIR = CONFIG_DIR / "contexts"
DB_PATH = CONFIG_DIR / "universal-launcher.db"
LOG_DIR = CONFIG_DIR / "logs"

# Créer les répertoires nécessaires
for dir_path in [CONFIG_DIR, PROFILES_DIR, CONTEXTS_DIR, LOG_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

class ProjectType(Enum):
    """Types de projets supportés"""
    DEVELOPMENT = "development"      # Projets de développement classiques
    LEARNING = "learning"            # Sessions d'apprentissage (comme 42)
    DEVOPS = "devops"               # Projets DevOps/Infrastructure
    RESEARCH = "research"           # Projets de recherche
    CUSTOM = "custom"              # Projets personnalisés

@dataclass
class ProjectProfile:
    """Profil de projet avec contexte optimisé"""
    id: str
    name: str
    type: ProjectType
    path: Path
    description: str

    # Configuration Claude
    claude_context: Dict[str, Any] = field(default_factory=dict)
    context_files: List[str] = field(default_factory=list)
    auto_include_patterns: List[str] = field(default_factory=list)

    # Configuration session
    session_name: Optional[str] = None
    working_directory: Optional[Path] = None
    environment_vars: Dict[str, str] = field(default_factory=dict)

    # Scripts et commandes
    pre_launch_script: Optional[str] = None
    post_launch_script: Optional[str] = None
    quick_commands: List[Dict[str, str]] = field(default_factory=list)

    # Métadonnées
    created_at: datetime = field(default_factory=datetime.now)
    last_used: Optional[datetime] = None
    usage_count: int = 0

    # État
    active: bool = False
    pid: Optional[int] = None

    def __post_init__(self):
        if isinstance(self.path, str):
            self.path = Path(self.path)
        if isinstance(self.working_directory, str):
            self.working_directory = Path(self.working_directory)

class UniversalProjectLauncher:
    """Launcher principal avec interface système tray"""

    def __init__(self):
        self.profiles: Dict[str, ProjectProfile] = {}
        self.active_sessions: Dict[str, Any] = {}
        self.icon = None
        self.init_database()
        self.load_profiles()

    def init_database(self):
        """Initialiser la base de données SQLite"""
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL,
                started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                ended_at TIMESTAMP,
                context_size INTEGER,
                tokens_used INTEGER,
                notes TEXT,
                FOREIGN KEY (profile_id) REFERENCES profiles(id)
            )
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                path TEXT NOT NULL,
                config JSON,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_used TIMESTAMP,
                usage_count INTEGER DEFAULT 0
            )
        """)

        conn.commit()
        conn.close()

    def load_profiles(self):
        """Charger tous les profils depuis les fichiers YAML"""
        for profile_file in PROFILES_DIR.glob("*.yaml"):
            with open(profile_file, 'r', encoding='utf-8') as f:
                profile_data = yaml.safe_load(f)
                profile = ProjectProfile(**profile_data)
                self.profiles[profile.id] = profile

    def save_profile(self, profile: ProjectProfile):
        """Sauvegarder un profil"""
        profile_file = PROFILES_DIR / f"{profile.id}.yaml"

        # Convertir en dict pour YAML
        profile_dict = asdict(profile)

        # Convertir les types non sérialisables
        profile_dict['type'] = profile.type.value
        profile_dict['path'] = str(profile.path)
        if profile.working_directory:
            profile_dict['working_directory'] = str(profile.working_directory)

        with open(profile_file, 'w', encoding='utf-8') as f:
            yaml.dump(profile_dict, f, default_flow_style=False, allow_unicode=True)

    def create_context_file(self, profile: ProjectProfile) -> Path:
        """Créer un fichier de contexte optimisé pour Claude"""
        context_file = CONTEXTS_DIR / f"{profile.id}_context.md"

        with open(context_file, 'w', encoding='utf-8') as f:
            f.write(f"# 🎯 Contexte Claude - {profile.name}\n\n")
            f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
            f.write(f"**Type:** {profile.type.value}\n")
            f.write(f"**Path:** {profile.path}\n\n")

            # Ajouter le contexte personnalisé
            if profile.claude_context:
                f.write("## 📋 Instructions Spécifiques\n\n")
                for key, value in profile.claude_context.items():
                    f.write(f"### {key}\n{value}\n\n")

            # Inclure les fichiers de contexte
            if profile.context_files:
                f.write("## 📁 Fichiers de Contexte\n\n")
                for file_path in profile.context_files:
                    full_path = profile.path / file_path
                    if full_path.exists():
                        f.write(f"### {file_path}\n```\n")
                        try:
                            with open(full_path, 'r', encoding='utf-8') as ctx:
                                f.write(ctx.read())
                        except Exception as e:
                            f.write(f"Erreur lecture: {e}")
                        f.write("\n```\n\n")

            # Ajouter les commandes rapides
            if profile.quick_commands:
                f.write("## ⚡ Commandes Rapides\n\n")
                for cmd in profile.quick_commands:
                    f.write(f"- **{cmd['name']}:** `{cmd['command']}`\n")
                    if 'description' in cmd:
                        f.write(f"  {cmd['description']}\n")
                f.write("\n")

        return context_file

    def launch_claude_session(self, profile_id: str):
        """Lancer une session Claude avec contexte optimisé"""
        profile = self.profiles.get(profile_id)
        if not profile:
            return

        # Mettre à jour les stats
        profile.last_used = datetime.now()
        profile.usage_count += 1

        # Créer le contexte
        context_file = self.create_context_file(profile)

        # Préparer l'environnement
        env = os.environ.copy()
        env.update(profile.environment_vars)

        # Exécuter pre-launch script si défini
        if profile.pre_launch_script:
            subprocess.run(profile.pre_launch_script, shell=True, env=env)

        # Construire la commande Claude
        working_dir = profile.working_directory or profile.path

        # Commande pour lancer Claude avec contexte
        if sys.platform == "win32":
            # Pour Windows (via WSL)
            cmd = f'wsl.exe bash -c "cd {working_dir} && claude --context {context_file}"'
        else:
            # Pour Linux/Mac
            cmd = f'cd {working_dir} && claude --context {context_file}'

        # Lancer dans un nouveau terminal
        if sys.platform == "win32":
            subprocess.Popen(
                f'start "Claude - {profile.name}" cmd /k {cmd}',
                shell=True,
                env=env
            )
        else:
            subprocess.Popen(
                f'gnome-terminal --title="Claude - {profile.name}" -- bash -c "{cmd}; exec bash"',
                shell=True,
                env=env
            )

        # Exécuter post-launch script si défini
        if profile.post_launch_script:
            subprocess.run(profile.post_launch_script, shell=True, env=env)

        # Sauvegarder le profil mis à jour
        self.save_profile(profile)

        # Logger la session
        self.log_session(profile_id)

    def log_session(self, profile_id: str):
        """Enregistrer une session dans la base de données"""
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        session_id = f"{profile_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        cursor.execute(
            "INSERT INTO sessions (id, profile_id) VALUES (?, ?)",
            (session_id, profile_id)
        )

        conn.commit()
        conn.close()

    def create_tray_icon(self):
        """Créer l'icône système tray"""
        # Créer une image pour l'icône
        image = Image.new('RGB', (64, 64), color='#2E86AB')
        draw = ImageDraw.Draw(image)
        draw.rectangle([16, 16, 48, 48], fill='white')
        draw.text((22, 24), 'UPL', fill='#2E86AB')

        # Créer le menu
        menu_items = []

        # Ajouter les profils groupés par type
        for project_type in ProjectType:
            type_profiles = [p for p in self.profiles.values() if p.type == project_type]
            if type_profiles:
                type_menu = []
                for profile in type_profiles:
                    type_menu.append(
                        pystray.MenuItem(
                            f"🚀 {profile.name}",
                            lambda _, p=profile.id: self.launch_claude_session(p)
                        )
                    )

                menu_items.append(
                    pystray.MenuItem(
                        f"📁 {project_type.value.title()}",
                        pystray.Menu(*type_menu)
                    )
                )

        menu_items.extend([
            pystray.MenuItem("─" * 20, None, enabled=False),
            pystray.MenuItem("⚙️ Configuration", self.open_config),
            pystray.MenuItem("📊 Statistiques", self.show_stats),
            pystray.MenuItem("➕ Nouveau Profil", self.create_new_profile),
            pystray.MenuItem("─" * 20, None, enabled=False),
            pystray.MenuItem("❌ Quitter", self.quit_app)
        ])

        menu = pystray.Menu(*menu_items)

        self.icon = pystray.Icon(
            "Universal Project Launcher",
            image,
            menu=menu
        )

    def open_config(self, icon, item):
        """Ouvrir la fenêtre de configuration"""
        # TODO: Implémenter l'interface de configuration
        messagebox.showinfo("Configuration", "Interface de configuration en développement")

    def show_stats(self, icon, item):
        """Afficher les statistiques d'utilisation"""
        # TODO: Implémenter l'affichage des stats
        messagebox.showinfo("Statistiques", "Statistiques en développement")

    def create_new_profile(self, icon, item):
        """Créer un nouveau profil via GUI"""
        # TODO: Implémenter la création de profil GUI
        messagebox.showinfo("Nouveau Profil", "Création de profil en développement")

    def quit_app(self, icon, item):
        """Quitter l'application"""
        self.icon.stop()
        sys.exit(0)

    def run(self):
        """Lancer l'application"""
        self.create_tray_icon()
        self.icon.run()

if __name__ == "__main__":
    launcher = UniversalProjectLauncher()

    # Créer un profil exemple si aucun n'existe
    if not list(PROFILES_DIR.glob("*.yaml")):
        print("Création des profils par défaut...")
        # Le profil 42-training sera créé dans le prochain fichier

    launcher.run()