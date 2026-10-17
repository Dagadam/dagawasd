# DagaWASD — Finestre di SketchUp per Claude Code: quello che il ponte
# (lib/bridge.rb) non raggiunge perché non è Ruby: pulsanti e caselle delle
# finestre native, avvisi modali (che bloccano anche il ponte), menu,
# cattura dello schermo, tasti e mouse simulati per giocare in modalità FPS.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\finestre.ps1 <comando> ...
#
#   elenca                          finestre di SketchUp (titolo, classe, modale)
#   controlli <finestra> [max] [livelli]   controlli di una finestra: tipo, nome, id, stato
#   premi <finestra> <controllo>    preme un pulsante, spunta una casella, sceglie una voce
#   indica <finestra> <controllo>   porta il cursore sul controllo e lo incornicia, senza premere
#   scrivi <finestra> <controllo> <testo>   riempie una casella di testo
#   menu <voce>[><voce>...]         menu della finestra principale, es. "Estensioni>DagaWASD>Impostazioni"
#   aspetta <finestra> [secondi]    finché la finestra compare (default 10 s)
#   sparita <finestra> [secondi]    finché la finestra non c'è più
#   chiudi <finestra>               chiude la finestra come la X
#   primo <finestra>                porta la finestra in primo piano
#   mostra <finestra>               la rimostra se è a icona, senza fuoco (dice se lo era)
#   icona <finestra>                la riduce a icona, senza fuoco
#   posizione <finestra>            x y larghezza altezza, e su quale monitor
#   schermo <out.png> [<finestra>|vista [L A]]   lo schermo intero; una finestra
#                                   (anche coperta o ridotta a icona); vista = solo la vista 3D,
#                                   con le Overlay (cielo, nuvole) che write_image salta; con
#                                   L A la vista misura esattamente LxA (la finestra si allarga
#                                   per il tempo della cattura, anche oltre lo schermo)
#   tasti <passi...>                tastiera e mouse simulati verso SketchUp, es.
#       tieni:W+LShift:3000  premi:Esc  muovi:300,0  aspetta:500  ruota:120
#
# <finestra>: "principale", "avviso" (il messaggio aperto, es. UI.messagebox),
# una parte del titolo (maiuscole ignorate) o la classe esatta (es. QMessageBox).
# <controllo>: una parte del nome visibile, oppure =AutomationId esatto; col
# tipo davanti se lo stesso nome o id ce l'ha anche un contenitore, es.
# "Edit:=1001" (il nome del file nelle finestre Salva/Apri), "Button:Salva".
#
# Permesso e mouse li decide l'utente nel pannello, Sistema › Ponte Claude ›
# Finestre e tasti (letti da %APPDATA%\DagaWASD\settings.json a ogni avvio):
#   bridge_windows        spento (default) = solo elenca, controlli, posizione,
#                         aspetta, sparita; tutto il resto rifiutato
#   bridge_windows_mouse  acceso (default): prima di premere, scrivere o aprire
#                         un menu il cursore vero va sul controllo (in
#                         bridge_mouse_time secondi) e lo incornicia di verde
#
# Agisce solo sulle finestre del processo SketchUp. Preme i controlli con
# UI Automation: il mouse si muove solo per mostrarlo, il clic non passa da
# lui. I tasti simulati partono solo con SketchUp in primo piano: se il primo
# piano passa ad altro (l'utente ha cliccato altrove) si rilascia tutto e ci
# si ferma.
# Le pagine web dentro SketchUp (pannello DagaWASD, 3D Warehouse, Gestione
# estensioni) per UI Automation sono una superficie unica: dentro non si vede.
param([Parameter(Position = 0)][string]$Comando = '', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arg = @())

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

# Le scelte del pannello; senza file o senza chiave, i valori predefiniti di lib/config.rb
$Imp = @{ bridge_windows = $false; bridge_windows_mouse = $true; bridge_mouse_time = 0.6 }
$fileImp = Join-Path $(if ($env:APPDATA) { $env:APPDATA } else { $HOME }) 'DagaWASD\settings.json'
if (Test-Path $fileImp) {
  try {
    $j = Get-Content $fileImp -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in @($Imp.Keys)) { if ($null -ne $j.$k) { $Imp[$k] = $j.$k } }
  } catch { }   # illeggibile: restano i predefiniti, cioè tutto spento
}
$SoloLettura = @('elenca', 'controlli', 'posizione', 'aspetta', 'sparita', '')
if (-not $Imp.bridge_windows -and $SoloLettura -notcontains $Comando) {
  [Console]::Error.WriteLine("ERRORE: «$Comando» non è permesso: accendi Finestre e tasti in DagaWASD (Sistema › Ponte Claude)")
  exit 3
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class FinW {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  public static string ClassOf(IntPtr h) { var s = new System.Text.StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }

  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct PLACEMENT { public int len, flags, show; public int minX, minY, maxX, maxY; public RECT normal; }
  [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref PLACEMENT p);
  [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr h, ref PLACEMENT p);
  public static PLACEMENT Placement(IntPtr h) { var p = new PLACEMENT(); p.len = Marshal.SizeOf(typeof(PLACEMENT)); GetWindowPlacement(h, ref p); return p; }
  public static void Restore(IntPtr h, PLACEMENT p) { p.len = Marshal.SizeOf(typeof(PLACEMENT)); SetWindowPlacement(h, ref p); }
  // Né ingrandita né a icona, a x,y con quella misura
  public static void Normal(IntPtr h, int x, int y, int w, int hh) {
    var p = Placement(h); p.flags = 0; p.show = 4;   // SW_SHOWNOACTIVATE: senza rubare il fuoco
    p.normal.L = x; p.normal.T = y; p.normal.R = x + w; p.normal.B = y + hh;
    SetWindowPlacement(h, ref p);
  }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);

  // La vista 3D: fra le finestre figlie visibili larghe e alte almeno metà
  // della principale, la più piccola (le altre sono i contenitori Qt).
  public static RECT Viewport(IntPtr main) {
    RECT m; GetWindowRect(main, out m);
    int mw = m.R - m.L, mh = m.B - m.T;
    RECT best = m; long area = long.MaxValue;
    EnumChildWindows(main, (h, l) => {
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      int w = r.R - r.L, hh = r.B - r.T;
      if (w * 2 >= mw && hh * 2 >= mh && (long)w * hh < area) { area = (long)w * hh; best = r; }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT m; [FieldOffset(0)] public KEYBDINPUT k; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }

  public static uint ForegroundPid() {
    uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid;
  }

  // Frecce, Ins, Canc, Home, Fine, PagSu, PagGiù, Ctrl e Alt destri: tasti estesi
  static bool Extended(ushort vk) {
    return (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E || vk == 0xA3 || vk == 0xA5;
  }

  public static void Key(ushort vk, bool up) {
    INPUT[] i = new INPUT[1];
    i[0].type = 1;
    i[0].u.k.vk = vk;
    i[0].u.k.scan = (ushort)MapVirtualKey(vk, 0);
    i[0].u.k.flags = (uint)((up ? 2 : 0) | (Extended(vk) ? 1 : 0));
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }

  public static void Mouse(int dx, int dy, int wheel) {
    INPUT[] i = new INPUT[1];
    i[0].type = 0;
    i[0].u.m.dx = dx; i[0].u.m.dy = dy;
    i[0].u.m.data = (uint)wheel;
    i[0].u.m.flags = (uint)((dx != 0 || dy != 0 ? 0x0001 : 0) | (wheel != 0 ? 0x0800 : 0));
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }

  // Windows concede il primo piano solo a chi ha ricevuto l'ultimo input:
  // un Alt premuto e rilasciato sblocca il cambio.
  public static bool Focus(IntPtr h) {
    if (IsIconic(h)) ShowWindow(h, 9);
    if (GetForegroundWindow() == h) return true;
    SetForegroundWindow(h);
    Thread.Sleep(50);
    if (GetForegroundWindow() == h) return true;
    Key(0x12, false); Key(0x12, true);
    SetForegroundWindow(h);
    Thread.Sleep(100);
    return GetForegroundWindow() == h;
  }
}
'@
[void][FinW]::SetProcessDPIAware()

# «Mostra il mouse»: il cursore vero va sul controllo e una cornice verde lo
# indica. La cornice non prende né fuoco né clic (NOACTIVATE, TRANSPARENT).
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.Threading;
public class Cornice : Form {
  public Cornice(Rectangle r) {
    FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
    StartPosition = FormStartPosition.Manual;
    BackColor = Color.Magenta; TransparencyKey = Color.Magenta;
    Bounds = Rectangle.Inflate(r, 5, 5);
  }
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams {
    get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x80 | 0x20 | 0x8; return p; }   // NOACTIVATE TOOLWINDOW TRANSPARENT TOPMOST
  }
  protected override void OnPaint(PaintEventArgs e) {
    using (var pen = new Pen(Color.FromArgb(34, 197, 94), 4)) e.Graphics.DrawRectangle(pen, 2, 2, Width - 5, Height - 5);
  }
}
public static class Indicatore {
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);

  static void Tratto(int x0, int y0, int x1, int y1, int ms) {
    int n = Math.Max(1, ms / 15);
    for (int i = 1; i <= n; i++) {
      double t = (double)i / n;
      double e = t < 0.5 ? 2 * t * t : 1 - Math.Pow(-2 * t + 2, 2) / 2;   // parte piano, accelera, frena
      SetCursorPos((int)Math.Round(x0 + (x1 - x0) * e), (int)Math.Round(y0 + (y1 - y0) * e));
      Application.DoEvents();
      Thread.Sleep(15);
    }
  }

  // Cornice su r, cursore al centro di r in ms millisecondi. modo: 0 dritto,
  // 1 prima in verticale, 2 prima in orizzontale (nei menu una diagonale
  // passerebbe sopra altre voci e chiuderebbe il sottomenu aperto).
  public static Form Vai(Rectangle r, int ms, int modo) {
    var f = new Cornice(r);
    f.Show(); f.Refresh(); Application.DoEvents();
    POINT a; GetCursorPos(out a);
    int x = r.X + r.Width / 2, y = r.Y + r.Height / 2;
    if (modo == 1)      { Tratto(a.X, a.Y, a.X, y, ms / 2); Tratto(a.X, y, x, y, ms / 2); }
    else if (modo == 2) { Tratto(a.X, a.Y, x, a.Y, ms / 2); Tratto(x, a.Y, x, y, ms / 2); }
    else                { Tratto(a.X, a.Y, x, y, ms); }
    Aspetta(150);
    return f;
  }

  public static void Chiudi(Form f, int ms) {
    if (f == null) return;
    Aspetta(ms);
    f.Close(); f.Dispose();
  }

  static void Aspetta(int ms) {
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) { Application.DoEvents(); Thread.Sleep(15); }
  }
}
'@

function Indica($rett, [int]$modo = 0) {
  if (-not $Imp.bridge_windows_mouse) { return $null }
  if ($rett.Width -le 0 -or $rett.Height -le 0) { return $null }   # senza misura
  if (-not ([Windows.Forms.Screen]::AllScreens | Where-Object { $_.Bounds.IntersectsWith($rett) })) { return $null }   # fuori dagli schermi (finestra a icona)
  $ms = [int]([math]::Min([math]::Max([double]$Imp.bridge_mouse_time, 0.1), 2.0) * 1000)
  [Indicatore]::Vai($rett, $ms, $modo)
}
function Fine-Indica($f) { if ($f) { [Indicatore]::Chiudi($f, 350) } }

$UIA  = [System.Windows.Automation.AutomationElement]
$Tree = [System.Windows.Automation.TreeScope]
$CT   = [System.Windows.Automation.ControlType]

function Fail([string]$msg) { [Console]::Error.WriteLine("ERRORE: $msg"); exit 1 }

function Su-Pid {
  $p = @(Get-Process SketchUp -ErrorAction SilentlyContinue)
  if ($p.Count -eq 0) { Fail 'SketchUp non è aperto' }
  $p[0]
}

# Finestre del processo SketchUp: quelle di primo livello, nell'ordine dello
# schermo (la più in alto prima), più le finestre figlie della principale.
# Da SketchUp 2024 l'interfaccia è Qt: avvisi (QMessageBox) e finestre web
# (CommonWebDialog) stanno sotto la principale, non sul desktop.
# La principale si riconosce dalla classe (CMainFrame): MainWindowHandle del
# processo, con il pannello in primo piano, indica il pannello.
function Su-Finestre {
  $proc = Su-Pid
  $cond = New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, [int]$proc.Id)
  $top = @($UIA::RootElement.FindAll($Tree::Children, $cond))
  $main = $top | Where-Object { $_.Current.ClassName -eq 'CMainFrame' } | Select-Object -First 1
  if (-not $main) { $main = $top | Where-Object { $_.Current.NativeWindowHandle -eq [int]$proc.MainWindowHandle } | Select-Object -First 1 }
  $script:MainH = if ($main) { [int]$main.Current.NativeWindowHandle } else { [int]$proc.MainWindowHandle }
  $figlie = @()
  if ($main) {
    $cw = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, $CT::Window)
    $figlie = @($main.FindAll($Tree::Children, $cw))
  }
  @($top | Where-Object { $_ -ne $main }) + $figlie + @($main | Where-Object { $_ })
}

function Norm([string]$s) { ($s -replace '&', '' -replace '…', '' -replace '\.\.\.', '').Trim().ToLowerInvariant() }

function Trova-Finestra([string]$nome, [switch]$Muta) {
  $tutte = Su-Finestre
  if ($nome -eq 'principale') {
    $w = $tutte | Where-Object { $_.Current.NativeWindowHandle -eq $script:MainH } | Select-Object -First 1
  } elseif ($nome -eq 'avviso') {
    # Qt (2024+); prima un #32770 col titolo «SketchUp» (non Salva/Apri, che sono #32770 anche loro)
    $w = $tutte | Where-Object { $_.Current.ClassName -eq 'QMessageBox' } | Select-Object -First 1
    if (-not $w) { $w = $tutte | Where-Object { $_.Current.ClassName -eq '#32770' -and $_.Current.Name -eq 'SketchUp' } | Select-Object -First 1 }
  } else {
    $n = Norm $nome
    $w = $tutte | Where-Object { (Norm $_.Current.Name).Contains($n) -or (Norm $_.Current.ClassName) -eq $n } | Select-Object -First 1
  }
  if (-not $w -and -not $Muta) { Fail "nessuna finestra di SketchUp «$nome» (vedi: elenca)" }
  $w
}

function Descrivi($e) {
  $c = $e.Current
  $tipo = $c.ControlType.ProgrammaticName -replace '^ControlType\.', ''
  $extra = @()
  if ($c.AutomationId) { $extra += "id=$($c.AutomationId)" }
  if (-not $c.IsEnabled) { $extra += 'disattivo' }
  $o = $null
  if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$o)) { $extra += "stato=$($o.Current.ToggleState)" }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$o)) { $v = $o.Current.Value; if ($v) { $extra += "valore=«$v»" } }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$o)) { if ($o.Current.IsSelected) { $extra += 'scelto' } }
  "{0,-12} «{1}»  {2}" -f $tipo, $c.Name, ($extra -join ' ')
}

# Visita in ampiezza fino a $prof livelli: la finestra principale ha migliaia
# di elementi (Struttura, Console Ruby…) e FindAll(Descendants) non finisce più.
# Ritorna gli elementi per cui $filtro è vero, al massimo $max.
function Visita($radice, [int]$prof, [scriptblock]$filtro, [int]$max) {
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $trovati = New-Object System.Collections.Generic.List[object]
  $livello = @($radice)
  for ($d = 1; $d -le $prof -and $livello.Count -gt 0; $d++) {
    $prossimo = New-Object System.Collections.Generic.List[object]
    foreach ($e in $livello) {
      # gli elementi possono sparire mentre li si visita (liste che si aggiornano)
      try { $f = $walker.GetFirstChild($e) } catch { continue }
      while ($f) {
        $si = $false
        try { $si = & $filtro $f } catch { }
        if ($si) { $trovati.Add($f); if ($trovati.Count -ge $max) { return $trovati } }
        $prossimo.Add($f)
        try { $f = $walker.GetNextSibling($f) } catch { $f = $null }
      }
    }
    $livello = $prossimo
  }
  $trovati
}

function Trova-Controllo($win, [string]$nome) {
  $tipo = $null
  if ($nome -match '^([A-Za-z]+):(.+)$') { $tipo = $Matches[1]; $nome = $Matches[2] }   # es. Edit:=1001, Button:Salva
  $okTipo = { param($e) -not $tipo -or ($e.Current.ControlType.ProgrammaticName -eq "ControlType.$tipo") }
  if ($nome.StartsWith('=')) {
    $id = $nome.Substring(1)
    $c = Visita $win 10 { param($e) $e.Current.AutomationId -eq $id -and (& $okTipo $e) } 1
  } else {
    $n = Norm $nome
    # prima il nome esatto, poi quello che lo contiene
    $c = Visita $win 10 { param($e) (Norm $e.Current.Name) -eq $n -and (& $okTipo $e) } 1
    if ($c.Count -eq 0) { $c = Visita $win 10 { param($e) (Norm $e.Current.Name).Contains($n) -and (& $okTipo $e) } 1 }
  }
  if ($c.Count -eq 0) { Fail "nella finestra «$($win.Current.Name)» nessun controllo «$nome» (vedi: controlli)" }
  $c[0]
}

function Premi($c) {
  $o = $null
  if (-not $c.Current.IsEnabled) { Fail "«$($c.Current.Name)» è disattivato" }
  if ($c.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$o)) { $o.Invoke(); return 'premuto' }
  if ($c.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$o)) { $o.Toggle(); return "stato=$($o.Current.ToggleState)" }
  if ($c.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$o)) { $o.Select(); return 'scelto' }
  if ($c.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$o)) { $o.Expand(); return 'aperto' }
  # Pulsante Win32 che non si presenta come tale (finestre Salva/Apri): BM_CLICK,
  # in coda, perché il clic chiude una finestra modale e SendMessage aspetterebbe
  $h = [IntPtr]$c.Current.NativeWindowHandle
  if ($h -ne [IntPtr]::Zero -and [FinW]::ClassOf($h) -eq 'Button') { [void][FinW]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); return 'premuto (BM_CLICK)' }
  Fail "«$($c.Current.Name)» non si può premere senza il mouse"
}

# Voce di un menu appena aperto da $padre. Qt (SketchUp 2024+): la tendina
# è un QMenu figlio della voce che l'ha aperta. Win32 (versioni precedenti):
# una finestra #32768 di primo livello.
function Voce-Aperta($padre, [string]$nome) {
  $n = Norm $nome
  $cMenu = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, $CT::Menu)
  $cVoce = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, $CT::MenuItem)
  for ($t = 0; $t -lt 20; $t++) {
    $tendine = @($padre.FindAll($Tree::Children, $cMenu)) + @(Su-Finestre | Where-Object { $_.Current.ClassName -eq '#32768' })
    foreach ($m in $tendine) {
      $voci = @($m.FindAll($Tree::Children, $cVoce))
      $v = $voci | Where-Object { (Norm $_.Current.Name) -eq $n } | Select-Object -First 1
      if (-not $v) { $v = $voci | Where-Object { (Norm $_.Current.Name).StartsWith($n) } | Select-Object -First 1 }
      if ($v) { return $v }
    }
    Start-Sleep -Milliseconds 100
  }
  $null
}

# Con Qt una voce attivata via UI Automation esegue il comando ma lascia
# aperte le tendine (un clic vero le chiuderebbe): si richiudono dall'ultima
# alla prima. Se una resta aperta, Esc, ma solo con la finestra principale in
# primo piano (con la tendina aperta lo è ancora): se il comando ha aperto un
# dialogo, il primo piano è suo e un Esc lo chiuderebbe. Ritorna quante
# tendine restano aperte.
function Chiudi-Menu($aperti) {
  if ($aperti.Count -eq 0) { return 0 }
  for ($i = $aperti.Count - 1; $i -ge 0; $i--) {
    $o = $null
    try { if ($aperti[$i].TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$o)) { $o.Collapse() } } catch { }
  }
  $cMenu = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, $CT::Menu)
  $aperte = {
    @($aperti | Where-Object {
      try { $m = $_.FindFirst($Tree::Children, $cMenu); $m -and -not $m.Current.IsOffscreen } catch { $false }
    }).Count
  }
  for ($t = 0; $t -le $aperti.Count; $t++) {
    Start-Sleep -Milliseconds 150
    $n = & $aperte
    if ($n -eq 0) { return 0 }
    if ([FinW]::GetForegroundWindow() -ne [IntPtr]$script:MainH) { return $n }
    [FinW]::Key(0x1B, $false); [FinW]::Key(0x1B, $true)
  }
  & $aperte
}

function Rett($e) {
  $r = $e.Current.BoundingRectangle
  [Drawing.Rectangle]::new([int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
}

# ── Tasti per nome ───────────────────────────────────────────────────
$VK = @{
  'esc' = 0x1B; 'invio' = 0x0D; 'enter' = 0x0D; 'spazio' = 0x20; 'space' = 0x20; 'tab' = 0x09
  'shift' = 0xA0; 'lshift' = 0xA0; 'rshift' = 0xA1; 'ctrl' = 0xA2; 'lctrl' = 0xA2; 'rctrl' = 0xA3
  'alt' = 0xA4; 'lalt' = 0xA4; 'ralt' = 0xA5; 'canc' = 0x2E; 'del' = 0x2E; 'backspace' = 0x08
  'su' = 0x26; 'giu' = 0x28; 'sinistra' = 0x25; 'destra' = 0x27; 'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27
  'pagsu' = 0x21; 'pgup' = 0x21; 'paggiu' = 0x22; 'pgdn' = 0x22; 'home' = 0x24; 'fine' = 0x23; 'end' = 0x23
}
1..12 | ForEach-Object { $VK["f$_"] = 0x6F + $_ }

function Vk([string]$t) {
  $k = $t.ToLowerInvariant()
  if ($VK.ContainsKey($k)) { return [uint16]$VK[$k] }
  if ($k.Length -eq 1 -and $k -match '[a-z0-9]') { return [uint16][char]$k.ToUpperInvariant() }
  Fail "tasto sconosciuto: $t"
}

$premuti = New-Object System.Collections.Generic.List[uint16]
function Rilascia-Tutto { foreach ($k in $premuti) { [FinW]::Key($k, $true) }; $premuti.Clear() }

function Sorveglia([int]$ms, [int]$suPid) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $ms) {
    if ([FinW]::ForegroundPid() -ne $suPid) {
      Rilascia-Tutto
      Fail 'SketchUp non è più in primo piano: tasti rilasciati, mi fermo'
    }
    Start-Sleep -Milliseconds 20
  }
}

# ── Comandi ──────────────────────────────────────────────────────────
switch ($Comando) {
  'elenca' {
    $fin = Su-Finestre; $main = $script:MainH
    foreach ($w in $fin) {
      $c = $w.Current
      $o = $null; $mod = ''
      if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$o) -and $o.Current.IsModal) { $mod = ' MODALE' }
      $pri = if ($c.NativeWindowHandle -eq $main) { ' (principale)' } elseif ($c.IsOffscreen) { ' nascosta' } else { '' }
      $r = Rett $w
      "«{0}»  classe={1}  {2},{3} {4}x{5}{6}{7}" -f $c.Name, $c.ClassName, $r.X, $r.Y, $r.Width, $r.Height, $mod, $pri
    }
  }
  'controlli' {
    if ($Arg.Count -lt 1) { Fail 'controlli <finestra> [max] [livelli]' }
    $w = Trova-Finestra $Arg[0]
    $max  = if ($Arg.Count -ge 2) { [int]$Arg[1] } else { 200 }
    $prof = if ($Arg.Count -ge 3) { [int]$Arg[2] } else { 5 }
    $tutti = Visita $w $prof { param($e) $e.Current.Name -or $e.Current.AutomationId } ($max + 1)
    $tutti | Select-Object -First $max | ForEach-Object { Descrivi $_ }
    if ($tutti.Count -gt $max) { "… e altri (alza max o livelli)" }
  }
  'premi' {
    if ($Arg.Count -lt 2) { Fail 'premi <finestra> <controllo>' }
    $c = Trova-Controllo (Trova-Finestra $Arg[0]) $Arg[1]
    $nome = $c.Current.Name                          # dopo il clic il controllo può non esserci più
    $f = Indica (Rett $c)
    try { $esito = Premi $c } finally { Fine-Indica $f }
    "«$nome»: $esito"
  }
  'indica' {
    # come premi, ma senza premere: cursore e cornice, anche con «Mostra il mouse» spento
    if ($Arg.Count -lt 2) { Fail 'indica <finestra> <controllo>' }
    $c = Trova-Controllo (Trova-Finestra $Arg[0]) $Arg[1]
    $Imp.bridge_windows_mouse = $true
    $f = Indica (Rett $c)
    if (-not $f) { Fail "«$($c.Current.Name)» non è su nessuno schermo" }
    Fine-Indica $f
    "indicato: «$($c.Current.Name)»"
  }
  'scrivi' {
    if ($Arg.Count -lt 3) { Fail 'scrivi <finestra> <controllo> <testo>' }
    $c = Trova-Controllo (Trova-Finestra $Arg[0]) $Arg[1]
    $f = Indica (Rett $c)
    $o = $null
    try {
    if ($c.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$o)) {
      $o.SetValue($Arg[2])
      "«$($c.Current.Name)» = «$($o.Current.Value)»"
    } else {
      # Casella Win32 che non si presenta come tale (nome del file nelle finestre Salva/Apri): WM_SETTEXT
      $h = [IntPtr]$c.Current.NativeWindowHandle
      if ($h -eq [IntPtr]::Zero -or [FinW]::ClassOf($h) -ne 'Edit') { Fail "«$($c.Current.Name)» non è una casella di testo" }
      [void][FinW]::SendMessage($h, 0x000C, [IntPtr]::Zero, $Arg[2])
      "«$($c.Current.Name)» = «$($Arg[2])» (WM_SETTEXT)"
    }
    } finally { Fine-Indica $f }
  }
  'menu' {
    if ($Arg.Count -lt 1) { Fail 'menu "Voce>Voce>Voce"' }
    $voci = $Arg[0] -split '>' | ForEach-Object { $_.Trim() }
    $w = Trova-Finestra 'principale'
    $barra = Visita $w 3 { param($e) $e.Current.ControlType -eq $CT::MenuBar } 1
    if ($barra.Count -eq 0) { Fail 'la finestra principale non ha la barra dei menu' }
    $barra = $barra[0]
    $n = Norm $voci[0]
    $v = @($barra.FindAll($Tree::Children, [System.Windows.Automation.Condition]::TrueCondition)) | Where-Object { (Norm $_.Current.Name) -eq $n } | Select-Object -First 1
    if (-not $v) { Fail "nella barra dei menu non c'è «$($voci[0])»" }
    $aperti = New-Object System.Collections.Generic.List[object]   # le voci di cui si è aperta la tendina
    $errore = $null
    for ($i = 0; $i -lt $voci.Count; $i++) {
      if ($i -gt 0) {
        $v = Voce-Aperta $v $voci[$i]
        if (-not $v) { $errore = "voce «$($voci[$i])» non trovata nel menu aperto"; break }
      }
      $o = $null
      # dalla barra si scende in verticale; verso un sottomenu, laterale, prima in orizzontale
      $f = Indica (Rett $v) $(if ($i -eq 0) { 0 } elseif ($i -eq 1) { 1 } else { 2 })
      try {
        if ($i -lt $voci.Count - 1) {
          if (-not $v.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$o)) { $errore = "«$($voci[$i])» non apre un sottomenu"; break }
          $o.Expand()
          $aperti.Add($v)
        } else {
          if (-not $v.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$o)) { $errore = "«$($voci[$i])» non è un comando"; break }
          $o.Invoke()
        }
      } finally { if ($f) { [Indicatore]::Chiudi($f, 120) } }
    }
    $restano = Chiudi-Menu $aperti        # anche quando qualcosa è andato storto
    if ($errore) { Fail $errore }
    "menu: $($voci -join ' › ')$(if ($restano) { " (tendina rimasta aperta: c'è un dialogo davanti)" })"
  }
  'aspetta' {
    if ($Arg.Count -lt 1) { Fail 'aspetta <finestra> [secondi]' }
    $s = if ($Arg.Count -ge 2) { [double]$Arg[1] } else { 10 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $s) {
      $w = Trova-Finestra $Arg[0] -Muta
      if ($w) { "comparsa: «$($w.Current.Name)» dopo $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s"; exit 0 }
      Start-Sleep -Milliseconds 150
    }
    Fail "«$($Arg[0])» non è comparsa in $s s"
  }
  'sparita' {
    if ($Arg.Count -lt 1) { Fail 'sparita <finestra> [secondi]' }
    $s = if ($Arg.Count -ge 2) { [double]$Arg[1] } else { 10 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $s) {
      if (-not (Trova-Finestra $Arg[0] -Muta)) { "sparita dopo $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s"; exit 0 }
      Start-Sleep -Milliseconds 150
    }
    Fail "«$($Arg[0])» è ancora aperta dopo $s s"
  }
  'chiudi' {
    if ($Arg.Count -lt 1) { Fail 'chiudi <finestra>' }
    $w = Trova-Finestra $Arg[0]
    if ($w.Current.NativeWindowHandle -eq $script:MainH) { Fail 'la finestra principale non la chiudo: chiuderebbe SketchUp' }
    $o = $null
    if (-not $w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$o)) { Fail 'questa finestra non si chiude così' }
    $nome = $w.Current.Name
    $r = Rett $w
    $f = Indica ([Drawing.Rectangle]::new($r.Right - 46, $r.Y, 46, 30))   # la X in alto a destra
    try { $o.Close() } finally { Fine-Indica $f }
    "chiusa: «$nome»"
  }
  'primo' {
    if ($Arg.Count -lt 1) { Fail 'primo <finestra>' }
    $w = Trova-Finestra $Arg[0]
    if (-not [FinW]::Focus([IntPtr]$w.Current.NativeWindowHandle)) { Fail 'Windows non ha concesso il primo piano' }
    "in primo piano: «$($w.Current.Name)»"
  }
  'mostra' {
    # Rimostra senza fuoco una finestra ridotta a icona: una vista a icona
    # non si ridisegna e le animazioni (video dei percorsi) si fermano.
    if ($Arg.Count -lt 1) { Fail 'mostra <finestra>' }
    $w = Trova-Finestra $Arg[0]
    $h = [IntPtr]$w.Current.NativeWindowHandle
    if ([FinW]::IsIconic($h)) { [void][FinW]::ShowWindow($h, 4); 'era a icona: rimostrata' } else { 'già visibile' }
  }
  'icona' {
    if ($Arg.Count -lt 1) { Fail 'icona <finestra>' }
    $w = Trova-Finestra $Arg[0]
    [void][FinW]::ShowWindow([IntPtr]$w.Current.NativeWindowHandle, 7)   # SW_SHOWMINNOACTIVE
    'ridotta a icona'
  }
  'posizione' {
    if ($Arg.Count -lt 1) { Fail 'posizione <finestra>' }
    $w = Trova-Finestra $Arg[0]
    $r = Rett $w
    $mon = [Windows.Forms.Screen]::AllScreens | Where-Object { $_.Bounds.IntersectsWith($r) } | ForEach-Object { $_.DeviceName -replace '^\\\\\.\\', '' }
    "{0} {1} {2} {3}  monitor: {4}" -f $r.X, $r.Y, $r.Width, $r.Height, $(if ($mon) { $mon -join ', ' } else { 'NESSUNO (fuori dallo schermo)' })
  }
  'schermo' {
    if ($Arg.Count -lt 1) { Fail 'schermo <out.png> [<finestra>]' }
    $out = [IO.Path]::GetFullPath($Arg[0])
    if ($Arg.Count -lt 2) {
      # lo schermo intero, così come si vede
      $r = [Windows.Forms.SystemInformation]::VirtualScreen
      $bmp = New-Object Drawing.Bitmap($r.Width, $r.Height)
      $g = [Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($r.X, $r.Y, 0, 0, $r.Size)
      $g.Dispose()
    } else {
      # una finestra con PrintWindow (2 = PW_RENDERFULLCONTENT: anche OpenGL,
      # le Overlay e le pagine web), anche se coperta o fuori dallo schermo.
      # Ridotta a icona darebbe 160x28: la si rimostra senza fuoco e poi si rimette.
      $vista = $Arg[1] -eq 'vista'
      $nome = if ($vista) { 'principale' } else { $Arg[1] }
      $w = Trova-Finestra $nome -Muta
      $hMain = [IntPtr]$script:MainH
      $mainIcona = $false
      if (-not $w -and [FinW]::IsIconic($hMain)) {
        # con la principale a icona le sue finestre (pannello…) sono nascoste anche loro
        $mainIcona = $true
        [void][FinW]::ShowWindow($hMain, 4); Start-Sleep -Milliseconds 900
        $w = Trova-Finestra $nome -Muta
      }
      if (-not $w) { if ($mainIcona) { [void][FinW]::ShowWindow($hMain, 7) }; Fail "nessuna finestra di SketchUp «$nome» (vedi: elenca)" }
      $h = [IntPtr]$w.Current.NativeWindowHandle
      $icona = [FinW]::IsIconic($h)
      $prima = [FinW]::Placement($h)
      $misura = $vista -and $Arg.Count -ge 4
      if ($icona -and -not $misura) { [void][FinW]::ShowWindow($h, 4); Start-Sleep -Milliseconds 700 }   # SW_SHOWNOACTIVATE
      try {
        if ($misura) {
          # Vista di WxH esatti: la finestra (non ingrandita) si allarga di
          # quanto manca, anche oltre lo schermo; le barre possono andare a
          # capo con la larghezza, quindi qualche giro.
          $vw = [int]$Arg[2]; $vh = [int]$Arg[3]
          [FinW]::Normal($h, 0, 0, $vw + 40, $vh + 200)   # da lì si corregge
          for ($giro = 0; $giro -lt 5; $giro++) {
            Start-Sleep -Milliseconds 900
            $wr = New-Object FinW+RECT; [void][FinW]::GetWindowRect($h, [ref]$wr)
            $v = [FinW]::Viewport($h)
            $dw = $vw - ($v.R - $v.L); $dh = $vh - ($v.B - $v.T)
            if ($dw -eq 0 -and $dh -eq 0) { break }
            [void][FinW]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, ($wr.R - $wr.L) + $dw, ($wr.B - $wr.T) + $dh, 0x0014)   # NOZORDER|NOACTIVATE
          }
          Start-Sleep -Milliseconds 1200                   # che SketchUp ridisegni alla misura nuova
        }
        $wr = New-Object FinW+RECT
        [void][FinW]::GetWindowRect($h, [ref]$wr)
        $tutta = New-Object Drawing.Bitmap(($wr.R - $wr.L), ($wr.B - $wr.T))
        $g = [Drawing.Graphics]::FromImage($tutta)
        $hdc = $g.GetHdc()
        $preso = [FinW]::PrintWindow($h, $hdc, 2)
        $g.ReleaseHdc($hdc); $g.Dispose()
        if (-not $preso) { Fail 'PrintWindow non ha catturato la finestra' }
        if ($vista) {
          $v = [FinW]::Viewport($h)
          $bmp = $tutta.Clone([Drawing.Rectangle]::new($v.L - $wr.L, $v.T - $wr.T, $v.R - $v.L, $v.B - $v.T), $tutta.PixelFormat)
          $tutta.Dispose()
        } else {
          $bmp = $tutta
        }
      } finally {
        if ($misura) { [FinW]::Restore($h, $prima) }    # posizione, misura e stato di prima
        elseif ($icona) { [void][FinW]::ShowWindow($h, 7) }   # SW_SHOWMINNOACTIVE: com'era
        if ($mainIcona) { [void][FinW]::ShowWindow($hMain, 7) }
      }
    }
    $bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png)
    "salvata: $out ($($bmp.Width)x$($bmp.Height))"
    $bmp.Dispose()
  }
  'tasti' {
    if ($Arg.Count -lt 1) { Fail 'tasti tieni:W+LShift:3000 premi:Esc muovi:300,0 ruota:120 aspetta:500' }
    $proc = Su-Pid
    [void](Su-Finestre)
    $hMain = [IntPtr]$script:MainH
    $eraIcona = [FinW]::IsIconic($hMain)                 # alla fine ci torna
    $prima = [FinW]::Placement($hMain)
    if (-not [FinW]::Focus($hMain)) { Fail 'Windows non ha concesso il primo piano a SketchUp' }
    try {
      foreach ($passo in $Arg) {
        $p = $passo -split ':'
        switch ($p[0].ToLowerInvariant()) {
          'tieni' {
            $tt = $p[1] -split '\+' | ForEach-Object { Vk $_ }
            foreach ($k in $tt) { [FinW]::Key($k, $false); $premuti.Add($k) }
            Sorveglia ([int]$p[2]) $proc.Id
            Rilascia-Tutto
          }
          'premi' {
            $tt = $p[1] -split '\+' | ForEach-Object { Vk $_ }
            foreach ($k in $tt) { [FinW]::Key($k, $false); $premuti.Add($k) }
            Sorveglia 60 $proc.Id
            Rilascia-Tutto
          }
          'giu' { $k = Vk $p[1]; [FinW]::Key($k, $false); $premuti.Add($k) }    # resta premuto fino a 'su' o alla fine
          'su'  { $k = Vk $p[1]; [FinW]::Key($k, $true); [void]$premuti.Remove($k) }
          'muovi' {
            # a piccoli passi: un salto grande il recentraggio del cursore di FPS lo taglierebbe
            $xy = $p[1] -split ','; $dx = [int]$xy[0]; $dy = [int]$xy[1]
            $n = [math]::Max(1, [math]::Ceiling([math]::Max([math]::Abs($dx), [math]::Abs($dy)) / 20))
            for ($i = 1; $i -le $n; $i++) {
              [FinW]::Mouse([int]($dx * $i / $n) - [int]($dx * ($i - 1) / $n), [int]($dy * $i / $n) - [int]($dy * ($i - 1) / $n), 0)
              Sorveglia 16 $proc.Id
            }
          }
          'ruota'   { [FinW]::Mouse(0, 0, [int]$p[1]) }
          'aspetta' { Sorveglia ([int]$p[1]) $proc.Id }
          default   { Fail "passo sconosciuto: $passo" }
        }
      }
    } finally {
      Rilascia-Tutto
      if ($eraIcona) { $prima.show = 7; [FinW]::Restore($hMain, $prima) }   # SW_SHOWMINNOACTIVE
    }
    "tasti inviati: $($Arg -join ' ')"
  }
  default {
    Get-Content $PSCommandPath -Encoding UTF8 | Select-Object -Skip 4 | Where-Object { $_ -like '#*' } | ForEach-Object { $_ -replace '^# ?', '' }
    if ($Comando) { exit 1 }
  }
}
