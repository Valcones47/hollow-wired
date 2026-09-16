# Hub Quickshell — log de progresso

Construção autônoma do hub (painel abaixo do relógio da waybar) usando Quickshell puro (QML), substituindo a tentativa anterior em eww. Sessão iniciada em 2026-09-14, snapshot snapper **#1382** (pré-instalação).

Regras que segui: só pacman/yay, sem dotfiles de terceiro (Caelestia não foi instalada nem copiada — só o motor Quickshell), screenshot + auto-checagem a cada etapa, decisões estéticas registradas aqui em vez de travar esperando resposta.

---

## Etapa 0 — checagem prévia

- `lm_sensors` já estava instalado e `sensors` já mostra a temperatura da CPU (`coretemp-isa-0000`) sem precisar rodar `sensors-detect`. **Não precisei carregar nenhum módulo de kernel novo** — a regra de parar pra te avisar antes do `sensors-detect` não chegou a valer.
- `nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,name --format=csv` funciona direto (RTX 3050 Laptop GPU).
- `quickshell` está nos repositórios oficiais (`extra`/`cachyos-extra-v4`), não precisou de AUR.

---

## Etapa 1+2 — infraestrutura + painel base

**Instalado:** `quickshell` 0.3.1-1.1 via `pacman` (não precisou de AUR/yay).

**Criado:**
- `~/.config/wallust/templates/quickshell-colors.json` — novo template wallust, gera `~/.cache/wallust/colors-quickshell.json` (16 cores + background/foreground em hex). Registrado em `~/.config/wallust/wallust.toml` (`[templates].quickshell`). Sem hook de reload — o QML lê via `FileView` com `watchChanges: true`, recarrega sozinho quando o wallpaper muda.
- `~/.cache/wallust/colors-quickshell.json` — gerado manualmente com os valores atuais da paleta (mesmos hex do `colors-waybar.css`), pra funcionar já sem precisar rodar o wallust de verdade agora.
- `~/.config/quickshell/qmldir` + `Theme.qml` — singleton com a paleta (color0-15, background, foreground, aliases `accent1/accent2/inactive/warning/critical` no mesmo esquema do waybar/eww) + `withAlpha()` helper + constantes de layout (`radius`, `gap`, `panelWidth`, `panelHeight`).
- `~/.config/quickshell/shell.qml` — `PanelWindow` ancorado só no topo (`anchors.top: true`, sem left/right — isso já centraliza horizontalmente sozinho, confirmado no screenshot), `WlrLayershell.namespace: "quickshell-hub"`, fundo com alpha 0.88 + blur do Hyprland, cantos arredondados (`radius: 16`), borda sutil na cor accent1. `visible: false` por padrão. `IpcHandler { target: "hub" }` com `toggle()`/`show()`/`hide()`.

**Editado:**
- `~/.config/hypr/hyprland.conf`: `exec-once = quickshell` (a versão em eww continua com `exec-once` também — não apaguei, só não desenvolvo mais nela, conforme pedido) + `layerrule = blur on, match:namespace quickshell-hub`.
- `~/.config/waybar/config.jsonc`: `clock.on-click` trocado de `eww open hub --toggle` para `quickshell ipc call hub toggle`.

**Verificação:** `hyprctl reload` sem erro, `quickshell -c default` sobe sem erro ("Configuration Loaded"), `quickshell ipc call hub toggle` alterna visibilidade. Screenshot em `~/quickshell-progress/etapa-1-2-painel-base.png` — painel centralizado embaixo do relógio, cantos arredondados ok, borda visível, blur puxando o wallpaper por trás. Nada cortado ou sobreposto.

**Decisão estética (minha, pra revisar):** tamanho do painel 460×580px, `radius: 16`, gap do topo `16px` (`Theme.gap * 2`). Alpha do fundo 0.88 (mais opaco que o hub antigo em eww, que usava 0.85 — ajustei um pouco pra compensar o fato de que aqui não tenho controle fino sobre a "vibrancy" do blur por trás, e um fundo mais opaco deixa o texto mais legível em cima de wallpapers muito claros/coloridos como o atual).

**Nota técnica:** `quickshell ipc call <target> <função>` às vezes ecoa a listagem de funções do target no stdout mesmo em chamadas bem-sucedidas (percebi isso com `show`; `toggle` não fez isso depois). Não é erro — confirmei visualmente que o painel abre/fecha corretamente nos dois casos. Como é só o `on-click` da waybar chamando, esse stdout nem aparece em lugar nenhum, não afeta nada.

**Bug real que apareci e corrigi:** com o `qmldir` já existindo (por causa do singleton `Theme`), o Quickshell passa a tratar a pasta como módulo QML explícito — os outros componentes locais (`Dashboard.qml`, `Media.qml`, etc.) pararam de ser resolvidos automaticamente como tipos ("X is not a type", de forma inconsistente/só alguns arquivos). Corrigido listando todos os componentes locais no `qmldir` também, não só o singleton.

**Nota sobre a sessão:** por volta dessa etapa a tela bloqueou sozinha (hypridle, 10 min sem input real — minhas chamadas de ferramenta não contam como atividade pro Hyprland). Achei por um momento que era o painel do Quickshell quebrado (tela preta com relógio gigante = tela de bloqueio do hyprlock, não o hub). Não mexi no hypridle/hyprlock, só aguardei destravar. A partir daí passei a tirar screenshot só da região do painel (`grim -g`) em vez da tela inteira, pra não capturar outras janelas suas por engano.

---

## Etapa 3 — aba Dashboard

**Criado:**
- `~/.config/quickshell/Dashboard.qml` — relógio grande (HH:mm), data por extenso, mini-calendário do mês (grade 7 colunas, dia atual destacado com círculo na cor accent2), resumo do sistema (Distro/Uptime/WM lidos via `Process` + `uptime -p` e `/etc/os-release`, refletindo o real), prévia do player via `Quickshell.Services.Mpris` nativo (sem precisar do playerctl).
- `~/.config/quickshell/Media.qml`, `Monitoring.qml`, `Workspaces.qml` — placeholders ("em construção") por enquanto, viram conteúdo real nas próximas etapas.
- Barra de abas em `shell.qml` (4 botões com ícone + rótulo, clique troca `currentTab`).

**Bugs que apareci e corrigi nessa etapa:**
1. Ícone da aba Monitoramento (``, fa-tachometer) não existe nessa build da Nerd Font — caiu no glifo de "?" (fallback de glifo ausente). Troquei pro `` (fa-bar-chart), que existe e renderiza certo.
2. Data saía em inglês ("Monday, 14 de September") porque `Qt.formatDateTime` usa o locale do sistema, que não está em pt-BR. Troquei por arrays de nomes de dia/mês escritos na mão em português — mesmo padrão que uso no resto do rice (nada depende de locale do SO).

**Verificação:** screenshot em `~/quickshell-progress/etapa-3-dashboard.png`. Nada cortado, texto legível, calendário bate com o dia certo (14/set/2026 = segunda-feira, célula "1" cai na coluna terça — confere: 1/set/2026 é terça). Abas com ícone certo depois da correção.

**Decisão estética (minha, pra revisar):** cabeçalho do mini-calendário usa iniciais em português (D S T Q Q S S) em vez de nome completo, pra caber na largura do painel. Dia atual marcado com círculo preenchido (accent2) + texto na cor de fundo, em vez de só um contorno — achei mais fácil de bater o olho e achar rápido.

---

## Etapa 4 — aba Mídia

**Criado:** `~/.config/quickshell/Media.qml` — capa do álbum (via `player.trackArtUrl` do `Quickshell.Services.Mpris`, com ícone de nota musical como placeholder quando não tem capa), título/artista/álbum, badge com o nome do app de origem (`player.identity`), barra de progresso com tempo atual/duração, controles anterior/play-pause/próxima. Estado vazio ("Nada tocando" + ícone) quando não tem nenhum player MPRIS ativo.

**Testado de verdade, não só "rodou sem erro":** como nada estava tocando nessa sessão, subi um tom de teste com `mpv --no-video av://lavfi:sine=...` (o pacote `mpv-mpris`, já instalado, expõe isso como fonte MPRIS de verdade) só pra ter um player real pra validar contra. Depois de testar, parei o mpv (`pkill`) — não fica rodando nem foi deixado como dependência do hub, foi só ferramenta de teste.

**Bugs que apareci e corrigi nessa etapa:**
1. **Layout quebrado** (título flutuando longe da capa, espaço vazio enorme): um `Item { Layout.fillHeight: true }` usado como "empurrador" dentro de uma coluna aninhada dentro de um `RowLayout` sem altura própria causou uma cadeia de `fillHeight` sem limite superior definido, e o QtQuick Layouts não resolveu isso do jeito que eu esperava. Corrigido removendo o spacer e usando `Layout.alignment: Qt.AlignTop` nos dois lados do RowLayout (capa e coluna de texto) em vez de tentar empurrar o badge pro fundo.
2. **Barra de progresso começando errada**: o MPRIS não empurra a posição continuamente durante a reprodução (só em eventos como seek/troca de faixa), então eu uso um `Timer` local pra avançar a exibição sozinho — mas ele só sincronizava com a posição real do player em mudanças, não na inicialização. Resultado: depois de reiniciar o Quickshell com uma música já tocando, a barra começava do zero em vez de refletir onde a música realmente estava. Corrigido sincronizando também em `onPlayerChanged`. Confirmei comparando `playerctl position` (170.85s) com o que apareceu no hub (2:51 ≈ 170.85s) — bateu.
3. Testei também a via inversa: pausei por fora com `playerctl pause` e o ícone do botão central trocou de ⏸ pra ▶ sozinho, confirmando que a reatividade com o estado real do MPRIS funciona nos dois sentidos.

**Verificação:** screenshot em `~/quickshell-progress/etapa-4-media.png` (com o mpv de teste tocando). Layout correto, nada cortado, cores certas, progresso e controles reagindo ao estado real.

---

## Etapa 5 — aba Monitoramento

**Checagem obrigatória antes de mexer em sensores (regra sua):** `sensors` já mostrava a temperatura da CPU de cara (`coretemp-isa-0000`, `Package id 0`), `lm_sensors` já instalado. **Não precisei rodar `sensors-detect`, não instalei nada, não carreguei nenhum módulo de kernel.** Esse era o único ponto que eu devia genuinamente parar e te avisar antes — não chegou a valer.

**Criado:**
- `~/.config/quickshell/Ring.qml` — anel circular de progresso reutilizável (Canvas 2D, sem depender de módulo Qt extra), usado pelos 4 cards.
- `~/.config/quickshell/Monitoring.qml` — grade 2×2 com CPU (uso % + temperatura), GPU RTX 3050 (uso % + temperatura via `nvidia-smi`), RAM (usado/total em GiB, com zram como texto secundário no mesmo card, sem anel separado — como você pediu) e Disco (usado/total em GiB). Cor do anel muda por severidade (`accent2` normal, `warning` ≥70%, `critical` ≥90%).

**Fontes de dado:**
- CPU: uso calculado por delta de `/proc/stat` (duas leituras com 1s de intervalo, sem depender de `mpstat` que não está instalado); temperatura via `sensors` (grep no "Package id 0").
- GPU: `nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits`.
- RAM: `free -b`. zram: `zramctl -b --noheadings`.
- Disco: `df -B1 /`.
- Pollers em `Quickshell.Io.Process`, intervalos diferentes por custo/volatilidade: CPU/GPU a cada 2.5s (a leitura de CPU já embute o sleep de 1s pro delta), RAM/zram a cada 5s, disco a cada 15s (muda pouco).

**Bugs reais que apareci e corrigi nessa etapa (RAM e zram vieram "NaN"/zerados no primeiro teste):**
1. `free -b` nessa máquina roda em locale pt-BR e imprime a linha como `Mem.:` (com ponto), não `Mem:` — meu `awk '/^Mem:/'` nunca batia. Corrigido forçando `LC_ALL=C` antes do `free` (e por consistência, também antes do `df`), assim o parsing não depende do idioma do sistema.
2. Usei `zramctl --output-bytes`, que não existe nessa versão do util-linux instalada (a flag certa é `-b`/`--bytes`). Corrigido pra `-b`.
Confirmei rodando os comandos direto no terminal antes de aceitar como corrigido, não só olhando o screenshot.

**Verificação:** screenshot em `~/quickshell-progress/etapa-5-monitoring.png`. Os 4 números batem com o que os comandos originais retornam quando rodados à mão (CPU/GPU/RAM/Disco). Layout 2×2 sem corte, anéis proporcionais ao valor, nada sobreposto.

**Decisão estética (minha, pra revisar):** limiares de cor do anel em 70% (amarelo/`warning`) e 90% (vermelho/`critical`) — os mesmos números que already uso nos estados `warning`/`critical` do módulo de bateria do waybar, pra manter consistência entre os dois lugares do rice que mostram esse tipo de gauge.

---

## Etapa 6 — aba Workspaces

**Criado:** `~/.config/quickshell/Workspaces.qml` — grade de cards (3 colunas, quebra sozinha), um por workspace "normal" (id positivo — o scratchpad especial fica de fora da grade de propósito). Cada card mostra o número, até 3 títulos de janela (com "+N" se tiver mais), fica destacado quando é o workspace focado. Clique chama `workspace.activate()`.

**Sem `hyprctl` via processo nenhuma vez** — usei o módulo nativo `Quickshell.Hyprland` (`Hyprland.workspaces.values`, cada um já vem com `.toplevels.values` e `.activate()`), que já existe pronto no Quickshell e atualiza sozinho via os eventos do socket do Hyprland, sem eu precisar rodar `hyprctl -j` em loop nem fazer polling.

**Testado de verdade:** abri 2 janelas kitty de teste no workspace 1 e uma terceira no workspace 2 (`hyprctl dispatch workspace 2` + abrir + voltar pro 1), confirmei que:
- O card do workspace 1 mostrou "Teste Um" e "Teste Dois" e ficou destacado (focado).
- O card do workspace 2 apareceu do lado, sem destaque, mostrando "Workspace Dois".
- Fechei as janelas de teste depois (`pkill` nos processos `sleep 300` que usei de placeholder — o `hyprctl dispatch closewindow` não fechou, aparentemente o kitty pediu confirmação por ter processo filho rodando; matei o processo filho direto) e voltei o Hyprland pro estado original (só workspace 1, sem janela nenhuma, exatamente como estava antes de eu mexer).

**Pendente pro seu julgamento:** não testei o clique de verdade (não tem `ydotool`/`wlrctl`/`ferramenta de clique sintético instalada, e não instalei uma só pra isso — pareceu escopo demais pra um teste). O método `activate()` existe de verdade na API do Quickshell (confirmei lendo os arquivos `.qmltypes` que vêm com o pacote) e o padrão de `MouseArea { onClicked: ... }` é idêntico ao que já testei funcionando nos botões da aba Mídia (que reagem certo ao estado real do MPRIS nos dois sentidos). Ainda assim, **teste o clique com o mouse de verdade** quando voltar — é o único pedaço interativo da etapa que não pude confirmar com screenshot sozinho.

**Verificação:** screenshots em `~/quickshell-progress/etapa-6-workspaces.png` (2 workspaces, janelas listadas certas, destaque certo).

---

## Resumo final

Hub completo, 4 abas funcionando (Dashboard, Mídia, Monitoramento, Workspaces), cores 100% do wallust (nenhuma paleta fixa no QML), sem instalar nem copiar nada da Caelestia — só o motor Quickshell, construído do zero.

### O que foi instalado
- `quickshell` 0.3.1-1.1, via `pacman` (repositório `extra`/`cachyos-extra-v4` — não precisou de AUR).
- Nada mais. `lm_sensors`, `nvidia-smi`, `playerctl`/MPRIS, `zramctl` já existiam no sistema.
- `mpv` foi usado só como ferramenta de teste temporária (aba Mídia) e já foi parado — não é dependência do hub.

### Arquivos criados
- `~/.config/quickshell/` — `qmldir`, `shell.qml`, `Theme.qml`, `Ring.qml`, `Dashboard.qml`, `Media.qml`, `Monitoring.qml`, `Workspaces.qml`.
- `~/.config/wallust/templates/quickshell-colors.json` — template novo do wallust.
- `~/.cache/wallust/colors-quickshell.json` — cache gerado (será sobrescrito pelo wallust de verdade na próxima troca de wallpaper).
- `~/quickshell-hub-progress.md` — este arquivo.
- `~/quickshell-progress/*.png` — screenshots de referência de cada etapa.

### Arquivos editados
- `~/.config/hypr/hyprland.conf` — `exec-once = quickshell` + `layerrule = blur on, match:namespace quickshell-hub`. (Os `exec-once` do eww/player-watch de antes **continuam lá**, intocados, só não uso mais aquele hub.)
- `~/.config/waybar/config.jsonc` — `clock.on-click` agora chama `quickshell ipc call hub toggle` em vez do comando do eww.
- `~/.config/wallust/wallust.toml` — nova entrada `[templates].quickshell`.

### Não toquei (conforme pedido)
rofi, keybinds, waywallen, kitty (além da paleta wallust que já existia), o resto da waybar, os arquivos em `~/.config/eww/` (continuam aí, só não são mais usados).

### Como reverter
- **Tudo de uma vez:** `sudo snapper -c root undochange 1382..0` (ou restaurar a snapshot **#1382**, criada antes de qualquer instalação desta sessão).
- **Só desligar o hub novo, sem desinstalar nada:** remover a linha `exec-once = quickshell` e a `layerrule` do `hyprland.conf`, e devolver o `clock.on-click` do waybar pra `eww open hub --toggle` (o hub antigo em eww continua funcional, os arquivos nunca saíram do lugar).
- **Desinstalar o Quickshell:** `sudo pacman -Rns quickshell` (remove `cpptrace`/`libdwarf` também se nada mais usar).
- **Tirar o template do wallust:** apagar a entrada `[templates].quickshell` do `wallust.toml` e o arquivo `~/.config/wallust/templates/quickshell-colors.json` (não afeta os outros templates).

### Decisões estéticas que tomei sozinho (pra você revisar quando voltar)
1. Painel 460×580px, cantos com `radius: 16`, 16px de espaço abaixo da waybar.
2. Fundo do painel com alpha 0.88 (um pouco mais opaco que o hub antigo em eww, pra compensar não ter controle fino sobre o blur nesse ponto).
3. Abas com ícone + rótulo de texto (não só ícone) — achei mais claro que ficar adivinhando o que cada ícone significa.
4. Mini-calendário com cabeçalho de dia da semana abreviado (D S T Q Q S S) e dia atual marcado com círculo cheio na cor accent2.
5. Limiares de cor dos anéis de monitoramento: 70% = amarelo (warning), 90% = vermelho (critical) — mesmos números que o módulo de bateria do waybar já usa.
6. Grade de workspaces em 3 colunas, cada card mostra até 3 títulos de janela + "+N" se tiver mais.
7. Fonte de ícones: CaskaydiaCove Nerd Font (mesma família de nerd font já usada no resto do rice).

### Pendências pro seu julgamento
- **Clique nos cards de Workspaces** não foi testado com clique de mouse de verdade (sem ferramenta de input sintético instalada) — código usa a API documentada (`workspace.activate()`), mesmo padrão que já confirmei funcionando nos controles da aba Mídia, mas vale um clique manual seu pra confirmar 100%.
- Ideia que ouvi você comentando em outra conversa enquanto eu trabalhava (vi por acaso numa janela do Claude Desktop aberta atrás, não mexi nem li o resto) sobre um botão de update numa barra lateral — não implementei nada disso aqui, é só um FYI caso você queira me pedir depois; o escopo desta sessão foi só o hub de cima, sem barra lateral, como você pediu no início.

---

## Etapa 7 — correções e polimento (pedido seu depois de ver o resultado)

Você voltou, mandou prints com referência de estética e apontou 3 problemas reais. Perguntei sobre a barra lateral das imagens 10-12 antes de mexer em qualquer coisa (contradizia o "sem barra lateral" do pedido original) — você confirmou **só o hub por enquanto**, então não toquei nisso.

**Bug 1 — painel redimensionava outras janelas ao abrir:** o `PanelWindow` do Quickshell reserva uma "exclusive zone" por padrão (`exclusionMode: Auto`), e o Hyprland encolhia as janelas tiled pra abrir espaço pro hub — o comportamento que você queria era só sobrepor. Corrigido com `exclusionMode: ExclusionMode.Ignore` em `shell.qml`. Efeito colateral: com isso o painel também parou de respeitar a exclusive zone da própria waybar (passou a nascer colado nela) — corrigido somando a altura da waybar (26px, `Theme.waybarHeight`) na margem do topo manualmente. **Testei de verdade**: abri uma janela kitty tiled, anotei posição/tamanho (`[10,36] [1900,1034]`), abri o hub, conferi que ficou idêntico — sem o fix, isso mudava.

**Bug 2 — aba Monitoramento desalinhada:** o `GridLayout` estava esticando pra preencher toda a altura da aba (`anchors.fill: parent` sem limitar), deixando um vão enorme entre a fileira CPU/GPU e a fileira RAM/Disco. Corrigido: grid não estica mais (`Layout.alignment: Qt.AlignTop` em vez de `fillHeight`), sobra de espaço vai pra um spacer no final em vez de ser distribuída entre as fileiras.

**Animações e "acabamento" adicionados** (isso era o "parece cru"):
- Abrir/fechar o hub: fade + leve escala (antes era instantâneo). O fechar espera a animação terminar antes de desmapear a janela de verdade.
- Trocar de aba: crossfade em vez de corte seco.
- Abas, cards de Workspaces e botões da aba Mídia: hover com cor/escala animada (antes só reagiam ao clique, sem feedback nenhum passando o mouse por cima).
- Anéis da aba Monitoramento: valor novo do poll anima suavemente até o número certo em vez de "pular".

**Barrinhas de áudio reagindo ao som** (aba Mídia, só aparecem enquanto algo está tocando): usei o `cava` (já estava instalado, não precisei instalar nada) em modo `raw` output (ascii, 12 barras, `~/.config/quickshell/cava.conf` novo), lido via `Quickshell.Io.Process` + `SplitParser`. Só roda enquanto `player.isPlaying` — não fica consumindo CPU à toa quando não tem nada tocando. **Testado de verdade** com o tom de teste do mpv de novo: as barras reagiram nas frequências certas (2 picos, batendo com um tom de 440Hz puro).

**Sobre o tema não virar claro:** não precisou de código novo — o `wallust.toml` já tem `style = "dark"` fixo (é o mesmo motivo que a barra do KDE/Plasma nunca fica clara nesta máquina). As cores mudam com o wallpaper, o estilo dark não.

**Não fiz nesta rodada (fora do escopo combinado, ou fica pra depois se você quiser):**
- Barra lateral (confirmado que é pra depois).
- Redesenho completo dos anéis pro estilo "arco duplo" das imagens 8-9 (temperatura como preenchimento do anel + uso% como selo pequeno do lado) — mantive uso% como valor principal do anel (como no pedido original: "uso % e temperatura"), só apliquei a correção de alinhamento e as animações. Se você quiser literalmente o estilo das imagens (temperatura dominando o anel), é uma mudança pequena, me avise.

**Verificação:** `hyprctl reload` sem erro, Quickshell recarregado sem erro nenhuma vez nessa rodada, testei os 3 pontos (redimensionamento, alinhamento, barras de áudio) com dados reais, não só olhando print.


---

## Etapa 8 — sidebar por hover, botão de update, hub estilo Caelestia, clipboard (2026-09-15)

**Snapshot:** `sudo snapper -c root create` → **#1409** (`pre-hub-fixes-2026-09-15`). Backups extras: `~/.config/quickshell/.bak-2026-09-15/` (QML antes desta etapa) e `~/.config/hypr/hyprland.lua.bak-2026-09-15-hub`.

**Achado importante:** o config ativo do Hyprland agora é `~/.config/hypr/hyprland.lua` (`hyprctl systeminfo` → `configProvider: lua`). O `hyprland.conf` não é mais lido — editar ele não tem efeito nenhum.

### Sidebar (EnergySidebar.qml)
- **Abre com hover** na borda direita, fecha sozinha ~350ms depois que o mouse sai. Fechada, não aparece nada: a janela é transparente e a `mask: Region` (região de input do layer-shell) fica reduzida a 3px na borda. Aberta, a região cresce pra coluna inteira, então dá pra chegar pela borda em qualquer altura. Atraso de 120ms pra abrir (passar o cursor rápido pela borda não abre).
- Saiu do "clicar fora" do hub (não precisa, fecha pelo hover).
- **Botão de update corrigido:** `cachy-update` é interativo (`.desktop` com `Terminal=true`); rodar sem terminal fazia o processo morrer sem mostrar nada. Agora abre `kitty --class cachy-update -e cachy-update`, fecha a barra, e reconta os updates quando o kitty fecha.
- Visual novo: pill centralizado verticalmente, ícones Material (Nerd Font), avatar em cima, update com badge, logout/reboot/shutdown com confirmação em 2 cliques (ícone vira ✓ vermelho por 3s). Confirmações desarmam quando a barra fecha.

### Hub
- **Pendurado na waybar** (sem vão, mesmo fundo alpha 0.85 + blur, cantos invertidos na junção) e desce de dentro da barra ao abrir — como a Caelestia.
- Abas: ícone em cima + rótulo, indicador deslizante animado, separador fino.
- Fonte do hub: Noto Sans (proporcional). Waybar continua mono.
- Tokens novos no Theme: `primary` (color10 — os accents do wallust eram escuros demais pra contraste), `textColor`, `subtext`, `surface`, `tile`, `tileHigh`.
- **Bug encontrado:** propriedade chamada `onSurface` → no QML, `on` + maiúscula é handler de sinal, a cor resolvia vazia (texto preto). Renomeado pra `textColor`/`subtext`.
- **Dashboard** refeita em grade de cards: clima (wttr.in por IP, via http — https falha a verificação TLS aqui), usuário/distro/WM/uptime em pt, hora vertical HH•••MM, calendário com dias dos meses vizinhos, barras de CPU/RAM/disco, player com capa redonda girando + controles.
- **Performance** (antes "Monitoramento") refeita: 3 gauges de 270° alinhados no mesmo eixo (GPU | CPU maior | Memória), temperatura no arco externo e uso% no interno (memória: RAM externo, disco interno), chips com valores absolutos (RAM, zram, disco) embaixo. Causa do desalinhamento antigo: anel de 96px ancorado em colunas de ~400px com legendas de larguras diferentes.
- `SysStats.qml` (singleton novo): pollers de CPU/GPU/RAM/disco compartilhados entre as abas e **só rodando com o hub aberto** (antes rodavam o tempo todo).
- Bug de layout corrigido: layouts aninhados têm `fillHeight: true` por padrão — a linha de cima da dashboard engolia a altura toda.
- `Ring.qml` removido (substituído por `Gauge.qml`). IPC: `qs ipc call hub tab N` novo. Obs: `qs ipc call hub show` não funciona pelo CLI (conflita com o subcomando `show` do próprio `qs ipc`); `toggle` funciona.

### Clipboard (cliphist)
- `cliphist` e `wl-clipboard` já estavam instalados.
- `hyprland.lua`: autostart `wl-paste --type text|image --watch cliphist store`; **Super+V** abre o histórico no rofi (selecionar copia de volta, cola com Ctrl+V). `togglefloating`, que estava no Super+V, foi pro **Super+Shift+V**.
- Testado: cópia entra no `cliphist list`. Entradas de teste apagadas depois.

### Layer rules (hyprland.lua)
- `quickshell-hub`: blur + `ignore_alpha = 0.3`; `quickshell-sidebar`: blur + `ignore_alpha = 0.3` (sem isso o blur pega as áreas transparentes).

### Verificação
Screenshots: `~/quickshell-progress/etapa-8-{dashboard,performance,media,workspaces,sidebar}.png`. O fechamento por clique fora foi confirmado por log (cliques reais durante os testes fechavam o hub).

### Não testado com mouse de verdade
- Hover da sidebar (sem ferramenta de input sintético — aberta via IPC pro screenshot). Testar passando o mouse na borda direita.
- Clique no botão de update abrindo o kitty.

### Ideias anotadas, não implementadas
- Abas Mídia e Workspaces ainda no visual antigo (só herdaram fonte/cores novas). (Workspaces mostrou o workspace 1 "vazio" — conferido com `hyprctl clients`, estava vazio de fato.)
- Avatar: coloque uma imagem em `~/.face` que o card de usuário já usa; a sidebar ainda tem placeholder.

---

## Etapa 9 — moldura em volta da tela, sidebar com trays e popups conectados, waybar maior (2026-09-15)

**Snapshot:** **#1410** (`pre-frame-sidebar-trays-2026-09-15`). Backups: `~/.config/quickshell/.bak-2026-09-15-frame/`, `~/.config/waybar/*.bak-2026-09-15-frame`, `~/.config/hypr/hyprland.lua.bak-2026-09-15-frame`.

Referência: vídeo da Caelestia (`~/Imagens/452581252-...mp4`), analisado por quadros extraídos com ffmpeg.

### Waybar
- Altura 26 → 34, fonte 12 → 14px (workspaces 15px). Módulo `tray` removido (trays agora na sidebar). `Theme.waybarHeight` = 34.

### Moldura (Frame.qml, novo)
- Borda de 10px (`Theme.frameThickness`) nas laterais e embaixo, colada na waybar, cantos internos com raio 20, mesmo fundo/blur da waybar. Layer `bottom`, sem input.
- Espaço pras janelas via `gaps_out = { top = 8, right = 18, bottom = 18, left = 18 }` no hyprland.lua. **Tentativa descartada:** superfícies invisíveis com exclusive zone nas laterais — faziam a waybar encolher pra 10..1910px.
- Confirmado: janelas tiled em [20,44] 1880×1016; pixels das bordas com a cor da waybar.

### Sidebar (EnergySidebar.qml reescrita)
- Continua escondida; a faixa da moldura direita é o gatilho do mouse. Ao abrir, a barra cresce de dentro da moldura (cantos invertidos na junção).
- Maior: 64px de largura, botões 46px, ícones 22px.
- Conteúdo: avatar (`~/.face`, recorte do rosto da imagem enviada), update com badge, **trays** (`Quickshell.Services.SystemTray`), logout/reiniciar/desligar (2 cliques).
- **Popups conectados:** passar o mouse em qualquer ícone faz sair um popup da lateral da barra, na altura do ícone. Barra + popup são um único contorno desenhado num Canvas (cantos invertidos popup↔barra). Trocar de ícone desliza/redimensiona o mesmo popup (260ms, OutCubic) com fade do conteúdo.
  - avatar: usuário + tempo ligado; update: total, repo/AUR, "clique para abrir"; energia: rótulo + estado da confirmação; tray: **menu do app desenhado dentro do popup** (TrayMenu.qml, novo), com separadores, check, submenus com "Voltar". Clique no ícone do tray = activate, botão do meio = secondaryActivate, scroll = scroll.
- `mask: Region` = faixa da moldura + barra + popup; o resto da janela deixa o clique passar.
- IPC de teste: `qs ipc call sidebar popup <avatar|update|logout|reboot|power>`, `trayPopup <n>`.

### Verificação
- Screenshots: `~/quickshell-progress/etapa-9-sidebar-{update,morph,power,tray}.png`. Menu do tray do waywallen renderizou com todas as entradas e submenu.
- **Não testado por mim:** hover real do mouse e cliques nos itens de menu do tray (sem input sintético). Pelo print, o usuário pareceu passar o mouse no avatar durante os testes e o popup abriu.

---

## Etapa 10 — avatar animado e wallpapers do waywallen travando (2026-09-15)

### Avatar
- Nova imagem: `~/Imagens/SidebarGif/rem-nobg.webp` (webp animado, 8 quadros, fundo transparente). Recortada no rosto (caixa 70,0–460,390, cobre o movimento em todos os quadros) → `~/.face.webp` (animado, 256px) e `~/.face` (1º quadro estático, pra SDDM etc.). Anterior guardado em `~/.face.bak-subaru.png`.
- Sidebar e Dashboard: `Image` → `AnimatedImage` com `source: ~/.face.webp`, `playing: visible`.

### Wallpapers que travavam — causa raiz
- `~/.var/app/org.waywallen.waywallen/config/waywallen/config.toml` tinha `[plugin.waywallen-video] render_node = "/dev/dri/renderD128"`.
- `renderD128` = **NVIDIA**, `renderD129` = **Intel** (a GPU ligada na tela). Dentro do Flatpak não existe driver NVIDIA pra versão 615.71.09 (só runtimes Mesa/VAAPI), então o renderer de vídeo morria ao abrir: `vk producer: Producer: no Vulkan device matches render_node /dev/dri/renderD128`. Todos os 7 wallpapers `video` da biblioteca eram afetados; os `scene` não (já iam pra Intel).
- Correção: `render_node = ""` (automático — padrão do plugin). Backup: `config.toml.bak-2026-09-15`.
- Testado: aplicado o wallpaper de vídeo id 15 → `Ready (drm_render=226:129)`, `decoder mode = vaapi-drm`, ~1,3% de CPU. Depois restaurado o wallpaper id 12 (cena).
- Logs do daemon agora ficam em `~/.var/app/org.waywallen.waywallen/.local/state/waywallen/logs/daemon/waywallen-current.log`.

### Lag — ainda não isolado
- Cena atual: ~2,5% CPU. Candidatos: vídeo 4K (id 32, `wallhack-awakening-sora`, 3840×2160), cenas pesadas renderizadas na iGPU Intel, `limitar_cpu.sh` (limita a CPU a 2,9 GHz), áudio ligado nos plugins. Falta o usuário dizer quais laggam.

### Polterghast travando (scene) — causa raiz e correção
- Até 14/09 a cena rodava na NVIDIA (`vulkan device: NVIDIA GeForce RTX 3050` nos logs). Em **14/09 21:44** o `pacman.log` registra `nvidia-utils/nvidia-open-dkms 610.57.04 → 615.71.09` + kernel 7.2.4. Depois do reboot de 15/09, toda cena caía na Intel UHD (TGL GT1), fraca demais pra ela.
- Motivo: o Flatpak só enxerga a NVIDIA com a extensão `org.freedesktop.Platform.GL.nvidia-<versão exata do driver>`; não havia nenhuma instalada pra 615.71.09.
- Correção: `flatpak install --user flathub org.freedesktop.Platform.GL.nvidia-615-71-09`.
- Testado: Polterghast (id 6) → `vulkan device: NVIDIA GeForce RTX 3050 Laptop GPU`, renderer ~3,7% CPU, NVIDIA ~38%. Deixado como wallpaper atual.
- **Atenção pra próximos updates do driver NVIDIA:** rodar `flatpak update` depois (instala a extensão da versão nova), senão os wallpapers voltam pra Intel.

---

## Etapa 11 — Fase 1 do backlog: QoL rápido (2026-09-15)

**Snapshot:** #1411 (`pre-qol-fase1`). Instalados: `hyprpicker`, `wf-recorder`, `wlsunset` (snapper #1412/#1413 pelo hook).

### Atalhos novos (hyprland.lua)
| Atalho | O quê |
|---|---|
| Super+Shift+S | print de região com anotação (grim+slurp+swappy; salva em ~/Imagens/Capturas de tela, config ~/.config/swappy/config) |
| Super+Shift+R | gravar região (de novo = parar) — `~/.local/bin/rice-record`, salva em ~/Vídeos/Gravações |
| Super+Ctrl+Shift+R | gravar tela inteira |
| Super+Shift+C | conta-gotas (hyprpicker, hex no clipboard + notificação) |
| Super+Shift+X | matar janela travada (`hyprctl kill`, clique na janela) |
| Super+' (tecla à esquerda do 1) | terminal drop-down (`rice-dropterm`, kitty class dropterm no special:dropterm, 70%×55%) |
| Super+Ctrl+R | emergência: reinicia quickshell/barra (`rice-restart`) |

### Regras de janela
- `dropterm`: flutuante, workspace especial, 70%×55%, topo centralizado — testado.
- `pip`: título Picture-in-Picture → flutuante, pin, 480×270 no canto inferior direito, sem roubar foco — **não testado** (precisa abrir um PiP no navegador).

### Autostart
- `wlsunset -l -23.35 -L -52.10 -t 4000 -T 6500` (luz noturna, Mandaguaçu).

### Sidebar
- Novos botões: **bloquear tela**, **modo café** (`IdleInhibitor` do Quickshell — inibe o escurecimento do hypridle), **luz noturna** (liga/desliga wlsunset), **GPU** (estado da NVIDIA via sysfs `runtime_status`, sem acordar a placa; popup lista apps com /dev/nvidia* aberto).
- **Gravação:** botão vermelho enquanto grava (clique para parar) + ponto vermelho pulsando na moldura direita com a barra fechada.
- **Reboot necessário:** `~/.local/bin/rice-reboot-needed` (kernel sem módulos instalados ou driver NVIDIA carregado ≠ instalado), checado a cada 10 min → ponto no botão reiniciar + motivo no popup.
- **Popup do update** com ações clicáveis: abrir cachy-update e **limpar cache de pacotes** (2 cliques; `~/.local/bin/rice-clean-cache` num kitty: `paccache -rk2`, `paccache -ruk0`, `yay -Sc`). Cache atual ~8,3 GB.

### Descartado
- "Escurecer antes do lock": o hypridle não bloqueia por ociosidade (decisão anterior do usuário), só escurece em 30 min — nada a fazer.

### Testado
- Gravação (2,9s 1920×1080), dropterm (regra + toggle), popups via IPC, `hyprctl configerrors` limpo, sem binds duplicados.

---

## Etapa 12 — Fase 2: barra do topo em Quickshell (substitui a waybar) (2026-09-15)

- `TopBar.qml` (novo). Waybar removida do autostart (linha comentada no hyprland.lua; config intacta em ~/.config/waybar). Layer rule `quickshell-bar` com blur + ignore_alpha. Exclusive zone 34px.
- Mesma linguagem da sidebar: hover num módulo → popup escorre da borda de baixo da barra, contorno único com cantos invertidos, desliza/redimensiona entre módulos, fecha ao sair (não fecha enquanto arrasta slider).
- **Esquerda:** workspaces (pontos; o ativo vira pill animado; urgente em vermelho; clique troca, scroll navega) + título da janela ativa.
- **Centro:** relógio HH:mm dd/MM — clique abre o hub (sinal direto, sem IPC).
- **Direita:**
  - gravação (só gravando; clique para);
  - microfone mutado (só quando mutado; clique desmuta);
  - **wifi** (Quickshell.Networking): liga/desliga, redes por sinal (conectada/salvas primeiro), clique conecta (rede salva direto; nova abre `nmtui-connect` num kitty), "Reiniciar rede" (2 cliques, nmcli off/on); escaneia só com o popup aberto;
  - **bluetooth** (Quickshell.Bluetooth): liga/desliga, dispositivos com bateria, clique conecta/desconecta/pareia, "Procurar dispositivos";
  - **volume** (Quickshell.Services.Pipewire): slider + mute da saída, troca de saída padrão, slider do microfone + troca de entrada, **mixer por aplicativo**; scroll no ícone ajusta, clique muta;
  - **brilho** (sysfs + brightnessctl): slider; scroll ajusta;
  - **bateria** (Quickshell.Services.UPower): %, estado, tempo restante, consumo W, ciclos (158), **perfil de energia** em 3 botões (substitui o powerprofile.sh da waybar).
- Componentes compartilhados novos: `PopTitle.qml`, `PopText.qml`, `PopAction.qml`, `PopSlider.qml` (sidebar refatorada pra usar).
- **Bug antigo corrigido:** `HyprlandWorkspace.activate()` usa a sintaxe antiga de dispatch, que quebra com o config em Lua → clique nos cards da aba Workspaces nunca funcionou desde a migração. Agora `Hyprland.dispatch("hl.dsp.focus({ workspace = N })")`.
- **Bug corrigido durante o teste:** ColumnLayout recalcula implicitWidth pelo conteúdo e ignora valor fixo → popups encolhiam e cortavam; agora usam `width` explícito.
- IPC de teste: `qs ipc call bar popup <audio|brightness|battery|wifi|bt>` / `hide`.
- Saúde da bateria: UPower não expõe nesse notebook (healthSupported=false); só os ciclos aparecem.

### Não testado por mim (precisa de mouse)
Arrastar sliders, conectar rede/bluetooth, trocar saída de áudio, clicar nos perfis de energia e nos workspaces, scroll nos módulos.

### Rollback da barra
Descomentar `hl.exec_cmd("waybar")` no hyprland.lua, remover o bloco `TopBar { ... }` do shell.qml, `hyprctl reload` e rodar `waybar`.

---

## Etapa 13 — Fase 3: especificações do PC, snapshots e notificações (2026-09-15)

**Snapshot:** #1414 (`pre-fase3-sysinfo`).

### Tela de especificações (SystemInfo.qml, novo)
- Abre clicando no avatar da sidebar (popup do avatar avisa). Cartão central 980×600 sobre fundo escurecido, abre com escala+fade, fecha clicando fora, no X ou com Esc. IPC: `qs ipc call sysinfo toggle`.
- Dados do `fastfetch --format json` (módulos escolhidos, ~20ms; sem OpenGL/Vulkan pra não acordar a NVIDIA) + sysfs da bateria.
- Seções: cabeçalho (avatar animado, nome, user@host, chips distro/WM/shell/uptime/notebook), Sistema, Processador e gráficos (2 GPUs + driver), Memória e armazenamento (barras RAM/zram/disco), Tela e áudio (1920×1080@144Hz, 17,3"), Bateria (**saúde 70%**: 2660/3815 mAh, 158 ciclos), Placa e rede (Acer Nitro AN517-54, BIOS Insyde V1.20, IP).

### Aba Snapshots (Snapshots.qml, novo — 6ª aba do hub)
- Lista via `sudo -n snapper --jsonout -c root list`, pares pre/post do pacman agrupados, ícone nos que estão no menu do Limine (8 mais recentes — regra do limine-snapper-sync; /boot não é legível sem root, então é pela regra, não lido do limine.conf).
- Criar snapshot com descrição (campo de texto), ver arquivos alterados (conta na hora + `snapper status` num kitty), apagar (2 cliques).
- **Restaurar:** `snapper rollback` NÃO funciona aqui (fstab `subvol=/@` fixo + Limine). A aba mostra o passo a passo real (boot no snapshot pelo Limine → `limine-snapper-restore` → reboot) e, quando detecta que o sistema está rodando dentro de um snapshot (`findmnt` com `/@/.snapshots/N`), mostra o botão "Tornar este snapshot permanente".
- README do projeto corrigido (ensinava `snapper rollback`).

### Aba Notificações (Notifications.qml, novo — 5ª aba do hub)
- `makoctl list -j` (na tela, com borda) + `makoctl history -j`; ícone do app, título, corpo (até 3 linhas). Atualiza a cada 4s com a aba aberta.
- `max-history=100` no ~/.config/mako/config (padrão era 5).
- Não perturbe (`makoctl mode -t do-not-disturb`).
- "Limpar": mako não tem comando pra apagar histórico → guarda o maior id em ~/.cache/quickshell/notif-cleared e esconde até ele (zera sozinho se o mako reiniciar).
- Limitação: mako não guarda horário das notificações.

### Outros
- Top bar: saúde da bateria agora aparece no popup (sysfs charge_full/charge_full_design; UPower não expõe).
- Layer rule `quickshell-sysinfo` com blur.

### Não testado por mim (precisa de mouse/teclado)
Clicar no avatar, digitar e criar snapshot, apagar snapshot, ver alterações, limpar notificações, não perturbe.

---

## Etapa 14 — Fase 4 (1/4): dock inferior + seção de jogos (2026-09-15)

**Snapshot:** #1416 (`pre-fase4-dock`).

- `Dock.qml` (novo). Mesma linguagem: sai de dentro da moldura de baixo (cantos invertidos), popups escorrem da borda de cima e deslizam entre ícones.
- **Aparece:** mouse na faixa central da moldura de baixo. Some ao tirar o mouse (450ms). (Auto-mostrar em workspace vazio foi removido na etapa 18 a pedido do usuário.)
- **Ícones:** fixados (zen, kitty, Dolphin, Claude, Discord, Spotify) · separador · apps abertos não fixados · separador · botão **Jogos**. Ícone cresce no hover, encolhe no clique.
- **Indicador:** pontos embaixo = janelas abertas (até 3); app com foco vira pill na cor primária.
- **Clique:** sem janela → abre; 1 janela → foca; várias → alterna. **Botão do meio:** nova janela.
- **Popup do app:** nome, lista de janelas (clique foca, X fecha), "Nova janela", "Fixar/Desafixar da dock".
- **Popup Jogos:** grade com Steam, Heroic, osu!lazer, r2modman, Hytale Launcher (item de gaming do backlog).
- Janelas via `ToplevelManager` do Quickshell (activate/close nativos, sem dispatch do Hyprland); ícones via `DesktopEntries`.
- Config: `~/.config/quickshell/dock.json` (`pins` e `games`, ids de .desktop) — dá pra editar à mão.
- Desenho: dock e popup são dois contornos no mesmo fill (união) — popup mais largo que a dock não cruza o contorno; o popup fica dentro da largura da dock quando cabe.
- IPC de teste: `qs ipc call dock toggle|games|hide`.

### Não testado por mim
Hover real na borda de baixo, clique nos ícones (abrir/focar/alternar), fechar janela pelo popup, fixar/desafixar, abrir jogo.

### Próximos da fase 4
Alt-tab com miniaturas ao vivo · zonas de encaixe ao arrastar · gaming (gamemode/mangohud automático).

---

## Etapa 15 — launcher próprio em Quickshell, reordenar dock, editar jogos, mouse sem pulo (2026-09-15)

**Snapshot:** #1417 (`pre-launcher-dock-drag`).

### Launcher (Launcher.qml, novo) — substitui o rofi no Super+R e na tecla Super sozinha
- Sai de dentro da moldura de baixo, no centro, com cantos invertidos; busca embaixo, resultados crescem pra cima (melhor resultado colado na busca). Entrada em cascata dos resultados, destaque que desliza entre linhas, ícone cresce no item atual.
- Busca: nome exato > começa com > palavra começa com > contém > nome genérico > palavras-chave > id > comentário > subsequência ("vsc" → Visual Studio Code); ignora acentos; empate desempata pelos mais usados (contagem salva no dock.json). Busca vazia = mais usados primeiro.
- Teclado: ↑/↓, Enter abre, Shift+Enter ou tecla Menu abre o menu do app, Esc fecha.
- **Botão direito:** Abrir · ações extras do .desktop (ex.: "Nova janela privada") · Fixar/Desafixar da dock · Adicionar/Remover dos jogos · **Editar entrada (kmenuedit)** — mesma função do script antigo do rofi.
- Clique fora fecha. A dock se esconde enquanto o launcher está aberto.
- O rofi continua instalado e ainda é usado pelo Super+V (clipboard). `rofi-app-launcher.py` não é mais chamado.

### DockConfig.qml (novo singleton)
- Fixados, jogos e contagem de uso compartilhados entre dock e launcher, em `~/.config/quickshell/dock.json`.

### Dock
- **Arrastar ícone fixado reordena** (os outros deslizam pra abrir espaço; clique continua funcionando se não arrastou).
- **Popup Jogos → Editar:** tiles balançam, arrastar reordena (tile alvo fica com borda), X remove; dica de adicionar pelo launcher.
- Abrir app pela dock também conta uso.

### Mouse
- `cursor.no_warps = true` no hyprland.lua: o mouse não é mais teleportado pro centro da janela ao focar (dock, launcher, Super+setas, etc.).

### Observação
- Ao testar, o dock.json tinha só `zen` e `discord` fixados (os outros 4 padrão sumiram) — não confirmado se foi desafixado pelo usuário ou bug. Usuário avisado.

### Não testado por mim
Digitar no launcher, navegação por teclado, menu do botão direito, kmenuedit, arrastar na dock, modo edição dos jogos.

---

## Etapa 16 — Fase 4 (2/4): Alt+Tab com miniaturas ao vivo (2026-09-15)

**Snapshot:** #1418 (`pre-alttab`). Instalado `wtype` (simulação de teclado pra testes; snapper #1419/#1420).

- `AltTab.qml` (novo): cartão central com miniatura **ao vivo** de cada janela (`ScreencopyView` do Quickshell), ícone, título e número do workspace; ordem = histórico de foco do Hyprland (`focusHistoryID`), abre já selecionando a janela anterior.
- Teclas: Alt+Tab / Alt+Shift+Tab (e Tab/setas com o overlay aberto) andam; **soltar o Alt troca**; Enter troca; Esc cancela; **Q fecha a janela selecionada**; clique numa miniatura troca; hover seleciona.
- Binds via **atalho global** (`hl.dsp.global("quickshell:alttab-next|prev")` + `GlobalShortcut` no QML) em vez de `qs ipc call` — sem abrir processo a cada toque. Janela do overlay fica sempre mapeada (sem input quando fechada) pra pegar o teclado o mais rápido possível num Alt+Tab rápido.
- **Bug encontrado e corrigido (afetava a dock também):** `Toplevel.activate()` só pede foco e o Hyprland ignora pra janelas em outro workspace (`misc.focus_on_activate=false`). Agora `DockConfig.focusWindow()` foca pelo endereço (`hl.dsp.focus({ window = "address:0x…" })`) — usado pelo Alt+Tab e pela dock (clique no ícone e na lista de janelas).
- Aviso no log `Failed to create gbm_bo ... across GPUs` → Quickshell cai pra buffer SHM nas miniaturas; funciona, só é um pouco menos eficiente (GPU híbrida).

### Testado
- Abrir pelo atalho global (via `hyprctl dispatch`), miniaturas ao vivo do Discord e do Zen, Enter trocando pra janela de outro workspace, Esc fechando.

### Não dá pra testar daqui
- O Hyprland **ignora atalhos vindos de teclado virtual** (wtype): nem o Super+' do dropterm dispara. E `wtype -M alt` não gera evento de tecla Alt. Então "segurar Alt, Tab, soltar Alt" com teclado real precisa do teste do usuário.

---

## Etapa 17 — Fase 4 (3/4): modo jogo (2026-09-15)

**Snapshot:** #1421 (`pre-modo-jogo`). Zonas de encaixe: **descartadas pelo usuário** (Super+arrastar já atende).

- Contexto: usuário já usa `game-performance prime-run gamemoderun %command%` nas opções da Steam; MangoHud já configurado via GOverlay (toggle Shift_R+F9) — config dele **não foi alterada**.
- `~/.local/bin/rice-gamemode on|off`: on = `hyprctl eval` desligando blur, sombra e animações + perfil Desempenho (só se não estava) + notificação; off = `hyprctl reload` (volta tudo do hyprland.lua) + perfil anterior se foi alterado. Estado em `$XDG_RUNTIME_DIR/rice-gamemode`. Descobre `HYPRLAND_INSTANCE_SIGNATURE` sozinho (gamemoded roda como serviço do usuário).
- `~/.config/gamemode.ini` (novo): `[custom] start/end` chamando o script. `gamemoded` reiniciado.
- `GameMode.qml` (singleton novo): observa o estado; **automático** pra jogos sem gamemoderun (classe `steam_app_N`, `*.exe` do Wine/Heroic, `osu!`, `hytale`, `gamescope`) segurando `gamemoderun sleep infinity` enquanto a janela existir; **manual** pelo botão.
- Sidebar: botão **Modo jogo** (gamepad; destaca ativo) com popup do motivo (automático/manual/gamemoderun). Top bar: ícone de gamepad enquanto ativo.

### Testado
`gamemoderun sleep 6`: blur/animações desligaram, estado gravado, gamemoded ativo, ícone apareceu na top bar; ao terminar, blur/animações voltaram e o estado sumiu.

### Não testado
Detecção automática com jogo real (classes das janelas de osu!/Hytale/Heroic podem precisar de ajuste em `GameMode.gamePatterns`), botão manual por clique.

---

## Etapa 18 — sem MangoHud, modo jogo sem mexer no visual, todo jogo na NVIDIA com DLSS (2026-09-15)

**Snapshot:** #1422 (`pre-dgpu-jogos`).

### MangoHud removido
- `mangohud`, `lib32-mangohud` e `goverlay` eram exigidos pelo meta-pacote `cachyos-gaming-applications` → meta-pacote removido junto.
- **ERRO MEU durante a remoção:** o passo que marcaria os outros apps do meta-pacote como explícitos falhou (lista vazia) e o `pacman -Rns` rodou mesmo assim (não estava condicionado), removendo também **lutris, heroic-games-launcher-bin, 7zip, wqy-zenhei, ttf-nerd-fonts-symbols** e dependências. **Reinstalados na hora** (explícitos); configs em ~/.config intactas (pacman não mexe). Saíram de verdade só MangoHud/lib32-mangohud/goverlay, o meta-pacote e deps exclusivas do goverlay (qt6pas, lib32-glu/glew/libxmu/libxt/libsm/libice). ~/.config/MangoHud ficou (arquivos inertes).

### Modo jogo
- `rice-gamemode` não mexe mais em blur/sombra/animações: só perfil Desempenho (se não estava) + notificação, e restaura o perfil ao sair. Testado.

### Todo jogo na GPU dedicada + DLSS
- **Achado:** `prime-run` (`__VK_LAYER_NV_optimus=NVIDIA_only`) **não filtra o Vulkan** nesse driver 615 — a Intel continuava como 1ª placa. O que funciona: camada device_select do Mesa `MESA_VK_DEVICE_SELECT=10de:25a2` + `MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1` (só a RTX 3050 fica visível). Verificado com vulkaninfo e glxinfo.
- `~/.local/bin/game-run` (novo): prime-run + Mesa device select + `PROTON_ENABLE_NVAPI=1` (Proton liga DXVK-NVAPI e usa o nvngx.dll do driver → DLSS; jogos sem DLSS ignoram; opt-out por jogo: `PROTON_DISABLE_NVAPI=1 %command%`).
- **Steam:** variáveis no `Exec` do `~/.local/share/applications/steam.desktop` (todas as ações) → todo jogo herda, inclusive os instalados no futuro. Backup `steam.desktop.bak-2026-09-15`. Obs.: o cliente da Steam também passa a rodar na NVIDIA enquanto aberto.
- **Heroic:** `nvidiaPrime: true`, `autoInstallDxvkNvapi: true` e env `PROTON_ENABLE_NVAPI` + `MESA_VK_DEVICE_SELECT*` no padrão e nos 3 jogos (env existentes preservadas). Backup em `~/.config/heroic/.bak-2026-09-15`.
- **osu!lazer:** `~/.local/share/applications/osu-lazer.desktop` com `game-run`.
- **Hytale (flatpak):** `flatpak override --user --env=...` (prime + Mesa select).
- As opções por jogo que o usuário já tinha na Steam (`game-performance prime-run gamemoderun ...`) continuam funcionando; `MANGOHUD=1` numa delas agora é inerte.

---

## Etapa 19 — dock: some sempre ao tirar o mouse + número do workspace nos ícones (2026-09-15)

- **Bug relatado:** dock não sumia. Diagnóstico com `qs ipc call dock state` (novo): workspace 1 estava vazio de verdade e a regra "aparecer sozinha em workspace vazio" mantinha a dock visível. Regra removida — agora só aparece com o mouse na borda de baixo. Também tratado `onCanceled` no arraste (arraste interrompido não deixa a dock presa aberta). Verificado monitorando cursor × estado.
- **Número do workspace** no canto inferior esquerdo de cada ícone de app aberto: um número, ou vários (`1·3`) se tiver janelas em workspaces diferentes; `✦` = workspace especial (magic, dropterm). Badge fica na cor primária quando o app está em foco.

---

## Etapa 20 — interface/mouse lagados: tudo renderizava na NVIDIA (2026-09-15)

- **Medição:** Hyprland render ~1,2ms (debug overlay) → compor as camadas com blur NÃO era o gargalo. CPU ociosa.
- **Causa:** `/etc/environment` (global, todas as sessões) define `__NV_PRIME_RENDER_OFFLOAD=1` e `__GLX_VENDOR_LIBRARY_NAME=nvidia`. Hyprland e todo app herdavam → Quickshell carregava `libnvidia-glcore` e desenhava na NVIDIA com a tela na Intel; cada frame copiado entre GPUs via SHM (`Failed to create gbm_bo ... does not work across GPUs`).
- **Correção (só sessão Hyprland, sem root, sem mexer no Plasma):** `hl.env("__NV_PRIME_RENDER_OFFLOAD","0")` e `hl.env("__GLX_VENDOR_LIBRARY_NAME","mesa")` + `systemctl --user unset-environment ...` no autostart. Jogos continuam na NVIDIA (game-run/steam.desktop/Heroic definem as variáveis explicitamente).
- Verificado: Quickshell reiniciado com env corrigido carrega só Mesa (`libgallium`), 0 erros "across GPUs".
- **Pendente:** apps abertos antes (navegador, Discord, kitty) e o próprio Hyprland ainda têm o env antigo → **sair e entrar de novo na sessão** aplica em tudo.
- `/etc/environment` não foi alterado (precisa de sudo com senha; afeta o Plasma). Se o usuário quiser remover globalmente: `sudo sed -i '/__NV_PRIME_RENDER_OFFLOAD\|__GLX_VENDOR_LIBRARY_NAME/d' /etc/environment`.
- Bug corrigido de quebra: `rice-restart` subia a waybar porque achava "waybar" na linha comentada do hyprland.lua; agora só considera `hl.exec_cmd("waybar")` ativo.

---

## Etapa 21 — lag com o Zen na tela (2026-09-15)

- Sessão ainda não reiniciada (Hyprland de 07:17 com env antigo). Zen já reaberto às 15:37 com env corrigido (Mesa).
- Compositor com Zen visível: render ~1,05ms → Hyprland não é o gargalo.
- **Zen:** `prefs.js` tinha DMABUF, canvas 2D acelerado e GL thread-safe bloqueados pela blocklist (provável herança de quando rodava via offload NVIDIA). Criado `~/.zen/czlavxqk.Default (release)/user.js` forçando: `widget.dmabuf.force-enabled`, `gfx.canvas.accelerated.force-enabled`, `gfx.x11-egl.force-enabled`, `gfx.webrender.all`, `media.ffmpeg.vaapi.enabled`, `media.hardware-video-decoding.force-enabled`. Vale ao reabrir o Zen; apagar o arquivo desfaz. `intel-media-driver` presente (iHD). `libva-utils` não instalado (pacman estava travado por outra operação — não forcei).
- **Wallpaper:** a cena do waywallen continua renderizando na NVIDIA (~39%) e copiando pra Intel mesmo com janelas cobrindo a tela — `auto_replay` só pausa com janela maximizada/tela cheia (`any_window = "none"`). Proposto ao usuário pausar com qualquer janela na tela (decisão estética, não aplicado).

---

## Etapa 22 — Toggle de blur substituindo o modo café na sidebar (2026-09-15)

- **Substituição do botão café pelo toggle de blur:**
  - Criado o script `~/.local/bin/rice-blur-toggle` (com symlink em `~/.config/hypr/scripts/blur-toggle.sh`), compatível com a configuração em Lua do Hyprland (`hyprctl eval "hl.config({ decoration = { blur = { enabled = ... } } })"` em vez do comando legado `keyword`).
  - Suporta `status`, `on`, `off` e `toggle` (padrão sem argumentos) e envia notificações via `notify-send`.
  - Gerencia o estado através de `$XDG_RUNTIME_DIR/rice-blur-disabled`.
  - Atualizado `~/.config/hypr/scripts/blur-fullscreen-toggle.sh` para respeitar o estado desativado manualmente (não religa o blur ao sair de tela cheia se o usuário o desativou).
  - Adicionados os ícones `blur` (`\u{F00A3}`) e `blurOff` (`\u{F00A4}`) ao `~/.config/quickshell/Theme.qml`.
  - Atualizado `~/.config/quickshell/EnergySidebar.qml`: o botão e popout de modo café foram substituídos pelo controle de blur com detecção em tempo real e atualização dinâmica de ícone e cor primária.
  - Atualizado `~/.config/hypr/hyprland.lua`: adicionado atalho de teclado `Super + B` vinculado a `rice-blur-toggle`.

---

## Etapa 23 — Correção de bugs no Dock e Launcher (2026-09-15)

- **Diagnóstico do desaparecimento de jogos e fixados no Dock:**
  - O Quickshell indexa os `.desktop` do sistema (`DesktopEntries`) de forma assíncrona.
  - No código anterior, `dock.items` e `gamesPop.entries` chamavam diretamente o método C++ `DesktopEntries.byId(id)`, sem acessar nenhuma propriedade QML reativa de `DesktopEntries`.
  - Como métodos não criam dependências reativas no motor do QML, a lista avaliava no exato momento da inicialização quando o `DesktopEntries` ainda estava vazio (retornando `[]`), e nunca mais recalculava até que `DockConfig.games` ou `DockConfig.pins` fossem modificados (adicionando ou removendo um item).
  - Além disso, se o ID precisasse de correspondência heurística (`heuristicLookup`) ou tivesse sufixo `.desktop`, `byId` falhava silenciosamente.
- **Correção no Dock (`Dock.qml` e `DockConfig.qml`):**
  - Adicionada a propriedade reativa `readonly property int _appsLoaded: DesktopEntries.applications.values.length`.
  - `items` e `gamesPop.entries` agora vinculam-se explicitamente a `_appsLoaded`, recalculando e populando instantaneamente assim que o Quickshell termina de carregar os `.desktop`.
  - Aprimorada a função `entryFor` para tratar sufixos `.desktop` e encadear `byId` com `heuristicLookup`.
  - Em `DockConfig.qml`: adicionado `watchChanges: true` e `onFileChanged: reload()`. Removido `root.save()` no `onLoadFailed` para evitar sobrescrever a lista de fixados/jogos caso houvesse atraso de leitura no arquivo. Tratamento para sanear chaves `undefined` no registro de uso.
- **Correções no Launcher (`Launcher.qml`):**
  - **Reset de busca:** `input.text = ""` adicionado no `onOpenChanged` (anteriormente apenas `query = ""` era limpo, mas a atribuição por digitação anterior quebrava a ligação do campo de texto).
  - **Salto/desaparecimento visual de conteúdo:** O container interno do painel usava cálculo dinâmico de `y` relativo à altura em animação (`y: root.panelH - root.targetH`), fazendo com que o campo de busca e a lista caíssem para fora da tela e piscassem durante 280ms sempre que o número de resultados mudava. Corrigido ancorando a base do conteúdo ao rodapé do painel.
  - **Navegação pelo teclado:** Adicionado suporte às teclas `Tab` e `Shift+Tab` para navegar entre os resultados e wrap-around nas setas ↑/↓.
  - **Conflito mouse x teclado:** Substituído `onEntered` por `onPositionChanged` no delegate dos itens, evitando que o cursor do mouse parado resete a seleção enquanto o usuário navega com o teclado.
  - **Blindagem contra crash:** Adicionada verificação contra arquivos `.desktop` sem chave `Name=` no filtro de `allApps` e proteção com fallback seguro no `localeCompare`.

---

## Etapa 24 — Correção definitiva do bug visual de sobreposição no Launcher (2026-09-15)

- **Causa raiz da sobreposição:**
  - O `ListView` do `Launcher.qml` usa `verticalLayoutDirection: ListView.BottomToTop` para que o resultado mais relevante fique colado na caixa de pesquisa.
  - Havia uma animação de transição `populate: Transition` que animava a propriedade `y` com base em `pop.ViewTransition.destination.y`.
  - No Qt Quick, o cálculo de `ViewTransition.destination.y` com listas `BottomToTop` calcula as coordenadas de cima para baixo. Como o layout organiza de baixo para cima, o item 0 era animado para o Y do item 7, o item 1 para o do item 6, e assim por diante.
  - Isso fazia com que cada slot da lista ficasse com exatamente dois itens desenhados no mesmo Y (pares invertidos sobrepostos).
- **Correção:**
  - Removido o `populate: Transition` que interferia no posicionamento Y nativo do `ListView`.
  - Como o painel inteiro já anima a altura (`Behavior on panelH`), o efeito de abertura continua fluido, mas agora os itens ficam perfeitamente renderizados e sem sobreposição.
  - Verificado visualmente com screenshots capturados via `grim`.

---

## Etapa 25 — Inversão do Launcher: ordem alfabética crescente do topo para baixo (2026-09-15)

- **Mudança na direção e ordenação do Launcher (`Launcher.qml`):**
  - **Ordenação alfabética:** Quando a pesquisa está vazia (`q === ""`), a lista agora é estritamente ordenada em ordem alfabética crescente (A → Z) usando `(a.name || "").localeCompare(b.name || "")`.
  - **Direção da lista:** Mudado `verticalLayoutDirection` de `ListView.BottomToTop` para `ListView.TopToBottom`. Agora o item 0 (primeiro em ordem alfabética) fica no topo da lista.
  - **Navegação por teclado:** As teclas de seta foram ajustadas para o fluxo natural de cima para baixo:
    - Pressionar Seta para Baixo (`↓`) ou `Tab` avança para o próximo aplicativo (`currentIndex + 1`).
    - Pressionar Seta para Cima (`↑`) ou `Shift+Tab` retorna ao aplicativo anterior (`currentIndex - 1`).
  - **Reset de visualização:** Ao abrir o launcher ou ao alterar a busca, a seleção é resetada para o topo (`currentIndex = 0`) e a rolagem é posicionada no início com `list.positionViewAtIndex(0, ListView.Beginning)`.
  - **Proteção contra hover acidental durante animação:** A seleção por movimento do mouse (`onPositionChanged`) agora só é habilitada quando a animação de abertura do painel estiver concluída (`root.panelH >= root.targetH - 1`), impedindo que o cursor parado na tela roube o foco do primeiro item durante o surgimento do painel.
  - Verificado visualmente via screenshots e reiniciado com `rice-restart`.

