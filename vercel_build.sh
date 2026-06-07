#!/bin/bash
# Script de compilacion para Vercel (Instala Flutter temporalmente y compila)

echo "--- Iniciando instalacion de Flutter en Vercel ---"
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"

echo "--- Habilitando Flutter Web ---"
flutter config --enable-web

echo "--- Instalando dependencias ---"
flutter pub get

echo "--- Compilando la aplicacion ---"
flutter build web --release

echo "--- Preparando archivos para Vercel ---"
rm -rf public
cp -R build/web public

echo "--- Compilacion finalizada con exito ---"
