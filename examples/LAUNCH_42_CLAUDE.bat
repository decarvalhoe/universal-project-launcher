@echo off
:: ========================================
:: 42 Training - Claude Session Launcher
:: One-click pour démarrer session optimisée
:: ========================================

title 42 Training - Claude Session
color 0A

echo ========================================
echo    42 TRAINING - CLAUDE SESSION
echo    Preparation Piscine Lausanne 2026
echo ========================================
echo.

:: Générer le contexte optimisé
echo [1/4] Generation du contexte optimise...
wsl.exe -e bash -c "cd ~/.agent-conductor && python3 context_generator.py profiles/42-training.yaml"

:: Afficher l'état actuel
echo.
echo [2/4] Etat actuel du training...
wsl.exe -e bash -c "cd ~/42_training && cat progression.json | python3 -m json.tool | grep -E '(current_exercise|current_step|next_command)' | head -3"

:: Vérifier les modifications non sauvegardées
echo.
echo [3/4] Verification Git...
wsl.exe -e bash -c "cd ~/42_training && git status --short"

:: Lancer Claude avec le contexte
echo.
echo [4/4] Lancement de Claude avec contexte optimise...
echo.

:: Option 1: Si Claude CLI est installé
:: wsl.exe -e bash -c "cd ~/42_training && claude --context ~/.agent-conductor/contexts/42-training_context.md"

:: Option 2: Ouvrir un terminal WSL interactif avec instructions
wsl.exe -e bash -c "cd ~/42_training && echo '============================================' && echo '🎯 SESSION 42 TRAINING PRETE!' && echo '============================================' && echo '' && echo 'CONTEXTE CHARGE: ~/.agent-conductor/contexts/42-training_context.md' && echo '' && echo '📋 INSTRUCTIONS:' && echo '1. Le contexte est pret et optimise' && echo '2. Tu peux copier-coller le contexte dans Claude' && echo '3. Ou utiliser: claude --context ~/.agent-conductor/contexts/42-training_context.md' && echo '' && echo 'PROCHAINE COMMANDE A TAPER:' && grep 'next_command' progression.json | cut -d'\"' -f4 && echo '' && echo '============================================' && echo 'Tape \"go\" pour commencer!' && echo '============================================' && exec bash"

pause