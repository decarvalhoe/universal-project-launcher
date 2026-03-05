#!/bin/bash
# Script pour pousser sur GitHub avec le bon compte

echo "🚀 Pushing Universal Project Launcher to GitHub..."
echo "Repository: https://github.com/decarvalhoe/universal-project-launcher"
echo ""

# Configurer le remote
git remote remove origin 2>/dev/null
git remote add origin https://github.com/decarvalhoe/universal-project-launcher.git

echo "📝 Instructions pour pusher manuellement :"
echo ""
echo "1. Ouvre un navigateur et va sur:"
echo "   https://github.com/settings/tokens"
echo ""
echo "2. Génère un Personal Access Token avec les permissions 'repo'"
echo ""
echo "3. Execute cette commande en remplaçant TOKEN par ton token:"
echo "   git push https://TOKEN@github.com/decarvalhoe/universal-project-launcher.git main"
echo ""
echo "OU utilise SSH:"
echo "   git remote set-url origin git@github.com:decarvalhoe/universal-project-launcher.git"
echo "   git push -u origin main"
echo ""
echo "Le repository est déjà créé sur GitHub :"
echo "👉 https://github.com/decarvalhoe/universal-project-launcher"