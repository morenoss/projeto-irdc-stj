@echo off
REM Adiciona tudo ao commit
git add .
REM Pergunta mensagem do commit
set /p msg="Mensagem do commit: "
git commit -m "%msg%"
REM Atualiza do remoto antes de subir
git pull origin main
REM Envia as mudanças
git push
pause
