# Kernel Charcoal para SteamOS

[![build](https://github.com/zarpon/linux-charcoal-TD/actions/workflows/push.yml/badge.svg)](https://github.com/zarpon/linux-charcoal-TD/actions)

[English](README.md)

O Charcoal é um pacote de kernel experimental para Steam Deck, Asus ROG Ally e
outros PCs portáteis AMD. Ele é construído a partir do
[`linux-neptune`](https://gitlab.steamos.cloud/jupiter/linux-integration) da
Valve, com um conjunto de alterações de agendamento, memória, I/O, Wi-Fi e
suporte específico para portáteis, todas registradas na origem da compilação.

> **Alvo atual de compilação:** a tag mais recente da Valve que corresponde a
> `6.16.12-valve*`. Cada release inclui a revisão exata do código-fonte e a
> seleção de patches dinâmicos usada naquela compilação.

## Dispositivos suportados

| Dispositivo | Status | Observação |
| --- | --- | --- |
| Steam Deck (LCD) | ✅ Testado | Alvo principal |
| Steam Deck (OLED) | ✅ Testado | Alvo principal |
| Asus ROG Ally (RC71L) | ✅ Testado | Confirmado pela comunidade |
| Outros portáteis AMD | ❓ Não testado | Informe o resultado em uma issue |

## Patches e configuração aplicados

Antes da compilação, o workflow da release resolve os componentes mantidos
abaixo. O arquivo `patch-lock.json`, incluído no arquivo da release, é o
registro oficial dos caminhos, commits, origens e valores SHA-256 exatos dos
patches usados.

| Componente | O que é aplicado no Charcoal |
| --- | --- |
| [LRU Marie](https://github.com/firelzrd/lru_marie) | Habilita o caminho de recuperação de memória LRU Marie (`CONFIG_LRU_MARIE=y`). |
| [zram-ir](https://github.com/firelzrd/zram-ir) | Adiciona o controle de recompressão imediata do zram por meio de `vm.zram_recomp_immediate`. Em eventos de adição ou mudança do zram, o helper incluído reafirma esse valor e, antes de inicializar o dispositivo, configura LZ4 como compressor primário e ZSTD como recompressor de prioridade `1`. Ele preserva um dispositivo inicializado ou swap ativo em vez de redefini-lo e não cria um dispositivo zram adicional. |
| [ADIOS](https://github.com/firelzrd/adios) | Adiciona o escalonador Adaptive Deadline I/O Scheduler e o torna o escalonador MQ de I/O padrão. A regra udev instalada também seleciona `adios` para dispositivos de bloco compatíveis, exceto dispositivos loop e zram. |
| [Infinity Scheduler v4.6-gpu](https://github.com/galpt/infinity-scheduler/tree/v4.6-gpu/patches/arch/7.1) | Aplica a série completa `0001`–`0006`: estado-base, comportamento CFS/EEVDF, escalonamento de tempo real e escalonamento virtual de GPU DRM. |
| [POC Selector](https://github.com/firelzrd/poc-selector) | Habilita a seleção de CPU ociosa por bitmap (`CONFIG_SCHED_POC_SELECTOR=y`) no caminho de ativação de tarefas. |
| [Nap](https://github.com/firelzrd/nap) | Habilita o governador Neural Adaptive Predictor de CPU idle. O fragmento de configuração do Charcoal desabilita ladder, menu e teo e habilita o NAP. |

Para componentes que possuem patch oficial compatível com 6.16, o resolvedor
busca o patch upstream correspondente mais recente. Quando é necessário um
porte aprovado para 6.16.12, a compilação usa o porte local do repositório e
registra em `patch-lock.json` a fonte upstream mais nova que ele acompanha. A
série Infinity é sempre acompanhada a partir da branch upstream `v4.6-gpu` e
aplicada pelos portes locais aprovados para 6.16.12.

### Outras alterações incluídas

- **Limites do Vangogh:** eleva o máximo exposto de CPU de 3,5 GHz para 4,2 GHz
  e o máximo de PPT informado de 29 W para 50 W.
- **Compilador e CPU:** compilação com Clang/LLVM, Clang LTO completo, Polly e
  Zen 2 como arquitetura mínima de CPU.
- **Patches estáticos:** patches selecionados de Linux-TKG, Gentoo, CachyOS,
  OpenWrt, Qualcomm ath11k e commits fixados do Zen Kernel. Eles incluem, entre
  outros, suporte a futex waitv/fsync, compatibilidade de compilador e DKMS,
  correções de Wi-Fi e otimizações de compilação.
- **Configuração do kernel:** validação de entrada de áudio, sobrecarga de
  depuração e drivers ou subsistemas legados/sem uso selecionados são
  desabilitados.
- **Ajustes persistentes em tempo de execução:** instala sysctls de VM e
  writeback, configurações de boot para transparent huge pages e MGLRU, KSM
  desabilitado no boot e as configurações de cache de shaders Mesa para a
  sessão Steam.

> **Trade-off de segurança:** o Charcoal define explicitamente
> `CONFIG_CPU_MITIGATIONS=n`. As mitigações de vulnerabilidades de CPU ficam
> desabilitadas; instale-o somente em um dispositivo e modelo de ameaça em que
> essa escolha seja aceitável.

### Módulos incluídos

Estes módulos externos são compilados dentro dos pacotes, portanto não exigem
uma instalação DKMS separada:

| Módulo | Finalidade |
| --- | --- |
| [ryzen_smu](https://github.com/amkillam/ryzen_smu) | Acesso à SMU Ryzen para monitoramento e controles de energia. |
| [xone](https://github.com/dlundqvist/xone) | Driver para dongle sem fio do Xbox One. |
| [xpad-noone](https://github.com/forkymcforkface/xpad-noone) | Permite que xone/xpadneo controlem os dispositivos em vez do driver xpad conflitante. |
| [xpadneo](https://github.com/atar-axis/xpadneo) | Driver avançado para controles Xbox. |

## Instalação

Execute no modo Desktop do SteamOS:

```bash
curl -fsSL https://raw.githubusercontent.com/zarpon/linux-charcoal-TD/master/install-charcoal.sh -o install-charcoal.sh && bash install-charcoal.sh
```

O instalador sempre obtém a [última release
publicada](https://github.com/zarpon/linux-charcoal-TD/releases/latest). Antes
de chamar o `pacman`, ele verifica o SHA-256 do ZIP da release e o SHA-256 de
cada pacote interno. Ele instala os pacotes do kernel e dos headers Charcoal e
restaura o modo somente leitura do SteamOS mesmo se a transação do pacote
falhar.

Confirme a substituição de `linux-neptune` se o pacman solicitar. Depois,
reinicie e confira:

```bash
uname -a  # deve conter "charcoal"
```

Também é possível ver a versão do kernel no modo Jogo em
**Configurações → Sistema**.

![Versão do kernel mostrada no modo Jogo do SteamOS em Configurações → Sistema](https://i.ibb.co/KzRyb2j7/20260525103630-1.jpg)

Atualizações do SteamOS podem substituir o kernel instalado. Após uma
atualização, verifique `uname -a` e execute o instalador novamente se
`charcoal` não aparecer mais.

## Desinstalação

Para remover o Charcoal e voltar ao kernel Neptune padrão:

```bash
sudo steamos-readonly disable
_neptune=$(pacman -Qi $(pacman -Qq 'linux-charcoal*') | awk '/^Replaces/{print $3}')
sudo pacman -Rsn $(pacman -Qq 'linux-charcoal*')
sudo pacman -S "$_neptune"
sudo steamos-readonly enable
```

Depois, reinicie.

## Compilar a partir do código-fonte

O Docker fornece o ambiente Arch Linux esperado para a compilação:

```bash
git clone https://github.com/zarpon/linux-charcoal-TD.git
cd linux-charcoal-TD
docker build -t linux-charcoal .
docker run --rm -it -v "$PWD:/project" linux-charcoal bash
```

Dentro do container, resolva o conjunto atual de patches antes de compilar:

```bash
cd /project
python3 automation/resolve-latest-patches.py --write
makepkg -s
```

O resolvedor grava os arquivos `latest-*.patch` selecionados, atualiza o
`PKGBUILD` e cria `logs/patch-lock.json`. Revise essas alterações geradas
antes de distribuir uma compilação local. O workflow do GitHub realiza a mesma
resolução e validação de checksums antes de empacotar uma release.

Também é possível compilar diretamente em um sistema baseado em Arch. As
dependências incluem `llvm`, `clang`, `lld`, `polly`, `bc`, `cpio`,
`pahole`, `python`, `git` e `openssh`; consulte o `PKGBUILD` para a
lista completa.

## Contribuições

Relate bugs e resultados de compatibilidade de dispositivos no
[rastreador de issues](https://github.com/zarpon/linux-charcoal-TD/issues).
Pull requests devem ter como alvo `master`. Para uma mudança de patch ou de
configuração, inclua a origem, a compatibilidade com o kernel-alvo e o
resultado da validação.
