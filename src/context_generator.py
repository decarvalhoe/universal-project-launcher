#!/usr/bin/env python3
"""
Context Generator for Claude Sessions
======================================
Génère automatiquement un contexte optimal pour minimiser
les tokens et maximiser l'efficacité.
"""

import json
import yaml
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any
import subprocess

class ClaudeContextGenerator:
    """Générateur de contexte intelligent pour Claude"""

    def __init__(self, profile_path: str):
        """Initialiser avec un profil de projet"""
        with open(profile_path, 'r', encoding='utf-8') as f:
            self.profile = yaml.safe_load(f)

        self.project_path = Path(self.profile['path'])
        self.context_cache = {}
        self.max_context_size = 10000  # Limite de tokens approximative

    def generate_optimal_context(self) -> str:
        """Générer le contexte optimal pour une session"""
        context_parts = []

        # 1. Header avec métadonnées essentielles
        context_parts.append(self._generate_header())

        # 2. Instructions spécifiques du profil
        if 'claude_context' in self.profile:
            context_parts.append(self._format_instructions())

        # 3. État actuel du projet (intelligent)
        context_parts.append(self._analyze_project_state())

        # 4. Fichiers de contexte (avec cache)
        context_parts.append(self._include_context_files())

        # 5. Historique récent (si pertinent)
        context_parts.append(self._get_recent_history())

        # 6. Commandes rapides formatées
        context_parts.append(self._format_quick_commands())

        # Assembler et optimiser
        full_context = "\n\n".join(filter(None, context_parts))
        return self._optimize_context(full_context)

    def _generate_header(self) -> str:
        """Générer l'en-tête du contexte"""
        return f"""# 🎯 Session: {self.profile['name']}
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Type: {self.profile['type']}
Path: {self.profile['path']}

---"""

    def _format_instructions(self) -> str:
        """Formater les instructions Claude du profil"""
        instructions = []
        claude_context = self.profile.get('claude_context', {})

        for key, value in claude_context.items():
            # Nettoyer et formater proprement
            clean_value = value.strip()
            instructions.append(f"## {key.replace('_', ' ').title()}\n\n{clean_value}")

        return "\n\n".join(instructions)

    def _analyze_project_state(self) -> str:
        """Analyser l'état actuel du projet intelligemment"""
        state_info = []

        # Pour 42-training, lire la progression
        if self.profile['id'] == '42-training':
            progression_file = self.project_path / 'progression.json'
            if progression_file.exists():
                with open(progression_file, 'r', encoding='utf-8') as f:
                    progression = json.load(f)

                state_info.append("## 📊 État Actuel\n")
                state_info.append(f"**Exercice:** {progression['progress']['current_exercise']}")
                state_info.append(f"**Étape:** {progression['progress']['current_step']}")
                state_info.append(f"**Prochaine commande:** `{progression['next_command']}`")

                # Dernières erreurs pour apprentissage
                if progression.get('mistakes'):
                    state_info.append("\n### ⚠️ Erreurs récentes à retenir:")
                    for mistake in progression['mistakes'][-3:]:  # Dernières 3 erreurs
                        state_info.append(f"- **{mistake['command']}**: {mistake['learned']}")

        # Pour les projets dev, analyser git
        elif self.profile['type'] == 'development':
            git_dir = self.project_path / '.git'
            if git_dir.exists():
                try:
                    # Obtenir le statut git
                    result = subprocess.run(
                        ['git', 'status', '--porcelain'],
                        cwd=self.project_path,
                        capture_output=True,
                        text=True
                    )
                    if result.stdout:
                        state_info.append("## 📊 Git Status\n")
                        state_info.append("```")
                        state_info.append(result.stdout)
                        state_info.append("```")

                    # Dernier commit
                    result = subprocess.run(
                        ['git', 'log', '-1', '--oneline'],
                        cwd=self.project_path,
                        capture_output=True,
                        text=True
                    )
                    if result.stdout:
                        state_info.append(f"\n**Dernier commit:** {result.stdout.strip()}")
                except:
                    pass

        return "\n".join(state_info)

    def _include_context_files(self) -> str:
        """Inclure les fichiers de contexte avec cache intelligent"""
        included_files = []

        for file_pattern in self.profile.get('context_files', []):
            file_path = self.project_path / file_pattern

            if not file_path.exists():
                continue

            # Vérifier le cache (éviter de relire si non modifié)
            file_hash = self._get_file_hash(file_path)
            cache_key = str(file_path)

            if cache_key in self.context_cache and self.context_cache[cache_key]['hash'] == file_hash:
                content = self.context_cache[cache_key]['content']
            else:
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()

                    # Optimiser le contenu (retirer les lignes vides excessives)
                    content = self._optimize_file_content(content)

                    # Mettre en cache
                    self.context_cache[cache_key] = {
                        'hash': file_hash,
                        'content': content
                    }
                except Exception as e:
                    content = f"Erreur lecture: {e}"

            # Ajouter seulement si pas trop gros
            if len(content) < 2000:  # Limite par fichier
                included_files.append(f"### 📄 {file_pattern}\n\n```\n{content}\n```")

        if included_files:
            return "## 📁 Fichiers de Contexte\n\n" + "\n\n".join(included_files)
        return ""

    def _get_recent_history(self) -> str:
        """Obtenir l'historique récent pertinent"""
        history_parts = []

        # Pour 42-training, inclure les commandes récentes du bash history
        if self.profile['id'] == '42-training':
            try:
                result = subprocess.run(
                    ['tail', '-n', '20', Path.home() / '.bash_history'],
                    capture_output=True,
                    text=True
                )
                if result.stdout:
                    # Filtrer les commandes pertinentes
                    relevant_commands = []
                    for line in result.stdout.splitlines():
                        if any(keyword in line for keyword in ['echo', 'cat', 'ls', 'cd', 'mkdir', 'touch', 'rm']):
                            relevant_commands.append(line)

                    if relevant_commands:
                        history_parts.append("## 📜 Commandes Récentes\n")
                        history_parts.append("```bash")
                        history_parts.extend(relevant_commands[-10:])  # Dernières 10
                        history_parts.append("```")
            except:
                pass

        return "\n".join(history_parts)

    def _format_quick_commands(self) -> str:
        """Formater les commandes rapides"""
        commands = self.profile.get('quick_commands', [])
        if not commands:
            return ""

        formatted = ["## ⚡ Commandes Rapides\n"]
        for cmd in commands:
            formatted.append(f"- **{cmd['name']}**: `{cmd['command']}`")
            if 'description' in cmd:
                formatted.append(f"  → {cmd['description']}")

        return "\n".join(formatted)

    def _optimize_context(self, context: str) -> str:
        """Optimiser le contexte pour réduire les tokens"""
        # Retirer les espaces multiples
        import re
        context = re.sub(r'\n{3,}', '\n\n', context)

        # Retirer les espaces en fin de ligne
        context = '\n'.join(line.rstrip() for line in context.splitlines())

        # Tronquer si trop long
        if len(context) > self.max_context_size:
            context = context[:self.max_context_size] + "\n\n[... Context truncated for optimization ...]"

        return context

    def _get_file_hash(self, file_path: Path) -> str:
        """Calculer le hash d'un fichier pour le cache"""
        with open(file_path, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()

    def _optimize_file_content(self, content: str) -> str:
        """Optimiser le contenu d'un fichier"""
        lines = content.splitlines()

        # Retirer les lignes vides consécutives
        optimized = []
        prev_empty = False
        for line in lines:
            if line.strip():
                optimized.append(line)
                prev_empty = False
            elif not prev_empty:
                optimized.append(line)
                prev_empty = True

        return '\n'.join(optimized)

    def save_context(self, output_path: Optional[Path] = None):
        """Sauvegarder le contexte généré"""
        context = self.generate_optimal_context()

        if not output_path:
            output_path = Path.home() / '.agent-conductor' / 'contexts' / f"{self.profile['id']}_context.md"

        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(context)

        # Afficher les stats
        lines = context.count('\n')
        chars = len(context)
        approx_tokens = chars // 4  # Approximation

        print(f"""
✅ Contexte généré avec succès!

📊 Statistiques:
- Lignes: {lines}
- Caractères: {chars}
- Tokens (approx): {approx_tokens}
- Fichier: {output_path}

💡 Tips pour économiser des tokens:
- Le contexte est optimisé et mis en cache
- Seules les infos essentielles sont incluses
- Les fichiers trop gros sont exclus automatiquement
""")

        return output_path

if __name__ == "__main__":
    # Test avec le profil 42-training
    import sys

    if len(sys.argv) > 1:
        profile_path = Path(sys.argv[1])
    else:
        profile_path = Path.home() / '.agent-conductor' / 'profiles' / '42-training.yaml'

    if profile_path.exists():
        generator = ClaudeContextGenerator(str(profile_path))
        generator.save_context()
    else:
        print(f"❌ Profil non trouvé: {profile_path}")