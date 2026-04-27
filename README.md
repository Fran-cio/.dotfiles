# Francio's dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


> Este proyecto es de uso personal y no deberia ser forkeado. Usalo como inspiracion. 

## Instalacion

```sh
git submodule update --init --recursive
./install.sh
```

El script chequea las aplicaciones usadas por estas configs y pregunta antes de instalar lo que falte. Usa `~/.config` o `$XDG_CONFIG_HOME`, por lo que funciona tanto en Linux como en macOS.

Si solo queres recrear symlinks sin chequear aplicaciones:

```sh
DOTFILES_SKIP_INSTALL_CHECKS=1 ./install.sh
```

## Compatibilidad macOS/Linux

La `.zshrc` detecta el sistema con `uname`, agrega rutas solo si existen y carga plugins opcionales solo cuando estan instalados. Las rutas especificas de cada maquina pueden ir en archivos locales no versionados:

- Git: `~/.gitconfig.local`
- Zsh: `~/.zshrc.local`
