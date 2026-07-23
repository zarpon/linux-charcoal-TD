# Kernel Charcoal para SteamOS - Edição Vulcano 
Antes de instalar, por favor verifique se você está no canal estável de instalação do SteamOs 

[![build](https://github.com/zarpon/linux-charcoal-vulcano/actions/workflows/push.yml/badge.svg)](https://github.com/zarpon/linux-charcoal-vulcano/actions)

[English](README.md)

O Charcoal Vulcano é um pacote de kernel experimental para Steam Deck, Asus ROG Ally e
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
| [zram-ir](https://github.com/firelzrd/zram-ir) | Adiciona o controle de recompressão imediata do zram por meio de `vm.zram_recomp_immediate`. Um *drop-in* do `zram-generator` incluído substitui a configuração primária `zstd` do SteamOS antes da inicialização de `zram0`: LZ4 é o compressor primário e ZSTD é a recompressão de prioridade `1`. Um `ExecStartPre` de `systemd-zram-setup@` executa a mesma configuração antes de `disksize`, tornando o comportamento determinístico mesmo se uma versão antiga do generator não configurar algoritmos secundários. O helper udev reafirma o sysctl e fornece um fallback seguro; ele nunca redefine um dispositivo inicializado ou swap ativo e não cria um dispositivo zram adicional. |
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
curl -fsSL https://raw.githubusercontent.com/zarpon/linux-charcoal-vulcano/master/install-charcoal.sh -o install-charcoal.sh && bash install-charcoal.sh
```

O instalador sempre obtém a [última release
publicada](https://github.com/zarpon/linux-charcoal-vulcano/releases/latest). Antes
de chamar o `pacman`, ele verifica o SHA-256 do ZIP da release e o SHA-256 de
cada pacote interno. Em seguida, ativa o modo de desenvolvedor do SteamOS sem
interação para inicializar o `pacman`, instala os pacotes do kernel e dos
headers Charcoal e atualiza a configuração do bootloader. A ordem de
preferência é `grub-mkconfig`, `steamos-update-grub` e `update-grub`; se nenhum
estiver disponível, o instalador não informa sucesso. Ele reinstala os pacotes
verificados quando necessário, pois revisões de release do Charcoal podem mudar
enquanto a versão-base do kernel da Valve permanece a mesma.

O modo de desenvolvedor permanece ativado após a instalação; somente o sistema
de arquivos raiz do SteamOS volta ao modo somente leitura, inclusive quando a
transação do pacote ou a atualização do bootloader falhar.

Confirme a substituição de `linux-neptune` se o pacman solicitar. Depois,
reinicie e confira:

```bash
uname -a  # deve conter "charcoal"
```

O instalador intencionalmente não redefine o swap zram que já está ativo, pois
o kernel não permite trocar o compressor após a inicialização. O compressor
primário LZ4 e o recompressor ZSTD de prioridade `1` entram em vigor no
primeiro boot com o Charcoal. Após esse boot, confirme:

```bash
cat /sys/block/zram0/comp_algorithm
cat /sys/block/zram0/recomp_algorithm
```

`[lz4]` indica o compressor primário selecionado. Em `recomp_algorithm`, o
ZSTD aparece na linha de prioridade `1`.

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
git clone https://github.com/zarpon/linux-charcoal-vulcano.git
cd linux-charcoal-vulcano
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

## Compilação manual pelo GitHub

Para gerar uma compilação nova a partir do conjunto atual de patches, sem
alterar o repositório, abra [Build latest SteamOS Charcoal kernel](https://github.com/zarpon/linux-charcoal-vulcano/actions/workflows/push.yml), clique em **Run workflow** e selecione `master`.

- Mantenha **Publish the compiled packages as a GitHub release** ativado para
  publicar uma release normal para download depois que todas as validações
  passarem.
- Desative essa opção para apenas validar a compilação. Os pacotes e o lock de
  patches ficarão disponíveis como artefatos do workflow por 14 dias; nenhuma
  release será criada.

Cada execução manual resolve primeiro os patches upstream compatíveis mais
recentes e registra seus commits e SHA-256 exatos em `patch-lock.json`.

Também é possível compilar diretamente em um sistema baseado em Arch. As
dependências incluem `llvm`, `clang`, `lld`, `polly`, `bc`, `cpio`,
`pahole`, `python`, `git` e `openssh`; consulte o `PKGBUILD` para a
lista completa.

## Contribuições

Relate bugs e resultados de compatibilidade de dispositivos no
[rastreador de issues](https://github.com/zarpon/linux-charcoal-vulcano/issues).
Pull requests devem ter como alvo `master`. Para uma mudança de patch ou de
configuração, inclua a origem, a compatibilidade com o kernel-alvo e o
resultado da validação.
