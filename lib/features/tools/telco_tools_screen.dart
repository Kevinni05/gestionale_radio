import 'dart:math' as math;
import 'package:flutter/material.dart';

class TelcoToolsScreen extends StatefulWidget {
  const TelcoToolsScreen({super.key});

  @override
  State<TelcoToolsScreen> createState() => _TelcoToolsScreenState();
}

class _TelcoToolsScreenState extends State<TelcoToolsScreen> {
  static const Color bg = Color(0xFF08090D);
  static const Color card = Color(0xFF191A24);
  static const Color card2 = Color(0xFF20212B);
  static const Color cyan = Color(0xFFE6E6E6);
  static const Color green = Color(0xFF35D07F);
  static const Color orange = Color(0xFFFFB547);
  static const Color red = Color(0xFFFF5570);
  static const Color purple = Color(0xFFB47CFF);
  static const Color text = Colors.white;
  static const Color muted = Color(0xFFAAAAB4);

  int _tab = 0;

  final List<_TelcoTab> _tabs = const [
    _TelcoTab('Panoramica', Icons.dashboard_rounded),
    _TelcoTab('IP/CIDR', Icons.lan_rounded),
    _TelcoTab('VLAN', Icons.account_tree_rounded),
    _TelcoTab('5G/LTE', Icons.cell_tower_rounded),
    _TelcoTab('Radio', Icons.settings_input_antenna_rounded),
    _TelcoTab('Fibra', Icons.fiber_manual_record_rounded),
    _TelcoTab('Manutenzione', Icons.build_circle_rounded),
    _TelcoTab('Energia', Icons.battery_charging_full_rounded),
    _TelcoTab('Lista di controllo', Icons.fact_check_rounded),
    _TelcoTab('Report', Icons.description_rounded),
  ];

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _tab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: const Text(
          'Strumenti Telco',
          style: TextStyle(
            color: text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: text),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _tabsBar(),
            const SizedBox(height: 4),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(key: ValueKey(_tab), child: _content()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabsBar() {
    return SizedBox(
      height: 58,
      child: ScrollConfiguration(
        behavior: const _NoGlowScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          itemCount: _tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final selected = i == _tab;
            final tab = _tabs[i];

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _selectTab(i),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: selected ? cyan.withValues(alpha: .13) : card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? cyan.withValues(alpha: .55)
                          : Colors.white.withValues(alpha: .07),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tab.icon, size: 17, color: selected ? cyan : muted),
                      const SizedBox(width: 7),
                      Text(
                        tab.label,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          color: selected ? cyan : muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _content() {
    switch (_tab) {
      case 1:
        return _ipTools();
      case 2:
        return _vlanTools();
      case 3:
        return _fiveGTools();
      case 4:
        return _radioTools();
      case 5:
        return _fiberTools();
      case 6:
        return _maintenanceTools();
      case 7:
        return _energyTools();
      case 8:
        return _checklistTools();
      case 9:
        return _reportTools();
      default:
        return _dashboard();
    }
  }

  Widget _page(List<Widget> children) {
    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        children: children,
      ),
    );
  }

  Widget _dashboard() {
    return _page([
      _hero(
        Icons.settings_input_antenna_rounded,
        'TelcoTools Pro',
        'Suite operativa per tecnici, tecnici sul campo e manutentori di rete.',
        cyan,
      ),
      const SizedBox(height: 14),

      _dashboardTile(
        'IP / CIDR / VLSM',
        'Subnetting IPv4, IPv6 e pianificazione VLSM',
        Icons.lan_rounded,
        cyan,
        1,
      ),
      _dashboardTile(
        'VLAN',
        'Validazione VLAN, range e pianificazione',
        Icons.account_tree_rounded,
        green,
        2,
      ),
      _dashboardTile(
        '5G / LTE',
        'NR-ARFCN, EARFCN, frequenze, lunghezze d\'onda e RSRP',
        Icons.cell_tower_rounded,
        orange,
        3,
      ),
      _dashboardTile(
        'Collegamento radio',
        'EIRP, FSPL, Fresnel, azimuth, fade margin e link budget',
        Icons.settings_input_antenna_rounded,
        orange,
        4,
      ),
      _dashboardTile(
        'Fibra / PON',
        'Optical budget, attenuazione, RX e margine',
        Icons.fiber_manual_record_rounded,
        cyan,
        5,
      ),
      _dashboardTile(
        'Manutenzione stazioni',
        'PIM, VSWR, return loss, batterie, grounding, temperature e allarmi',
        Icons.build_circle_rounded,
        red,
        6,
      ),
      _dashboardTile(
        'Energia / DC',
        'Consumi, autonomia batteria, potenza DC e dimensionamento',
        Icons.battery_charging_full_rounded,
        green,
        7,
      ),
      _dashboardTile(
        'Lista di controllo',
        'Controlli preventivi per shelter, RRU, antenne e apparati',
        Icons.fact_check_rounded,
        purple,
        8,
      ),
      _dashboardTile(
        'Report tecnico',
        'Generazione di report testuale copiabile e condivisibile',
        Icons.description_rounded,
        green,
        9,
      ),

      const SizedBox(height: 8),
      _infoCard(
        'Suite manutenzione radio',
        'Le funzioni sono pensate come strumenti di supporto al tecnico. '
            'I valori reali devono essere confrontati con specifiche apparato, '
            'banda, normativa e procedure aziendali.',
        Icons.info_outline_rounded,
        cyan,
      ),
    ]);
  }

  Widget _dashboardTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    int tab,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectTab(tab),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .055)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ipTools() {
    return _page([
      _section(
        'IPv4 / IPv6 / CIDR / VLSM',
        'Calcoli di indirizzamento e subnetting.',
      ),
      const SizedBox(height: 12),
      _SubnetCard(),
      const SizedBox(height: 12),
      _Ipv6Card(),
      const SizedBox(height: 12),
      _VlsmCard(),
    ]);
  }

  Widget _vlanTools() {
    return _page([
      _section('VLAN', 'Pianificazione e verifica VLAN 802.1Q.'),
      const SizedBox(height: 12),
      _SimpleCalculatorCard(
        title: 'VLAN ID',
        icon: Icons.account_tree_rounded,
        color: green,
        fields: const ['VLAN ID'],
        hints: const ['es. 120'],
        calculate: (values) {
          final id = int.tryParse(values[0]);

          if (id == null || id < 1 || id > 4094) {
            return 'VLAN ID non valido.\nIntervallo utilizzabile: 1–4094.';
          }

          final reserved = id == 1 || (id >= 1002 && id <= 1005);

          return 'VLAN $id valida.\n'
              '${reserved ? 'Attenzione: VLAN riservata/precedente.' : 'ID utilizzabile.'}';
        },
      ),
      const SizedBox(height: 12),
      _SimpleCalculatorCard(
        title: 'Intervallo VLAN',
        icon: Icons.linear_scale_rounded,
        color: cyan,
        fields: const ['VLAN iniziale', 'VLAN finale'],
        hints: const ['100', '120'],
        calculate: (v) {
          final a = int.tryParse(v[0]);
          final b = int.tryParse(v[1]);

          if (a == null || b == null || a < 1 || b > 4094 || a > b) {
            return 'Intervallo VLAN non valido.';
          }

          return '${b - a + 1} VLAN nell’intervallo $a–$b.';
        },
      ),
      const SizedBox(height: 12),
      _SimpleCalculatorCard(
        title: 'Porte / VLAN',
        icon: Icons.device_hub_rounded,
        color: purple,
        fields: const ['Numero VLAN', 'Porte per VLAN'],
        hints: const ['10', '24'],
        calculate: (v) {
          final vlan = int.tryParse(v[0]);
          final ports = int.tryParse(v[1]);

          if (vlan == null || ports == null || vlan <= 0 || ports <= 0) {
            return 'Inserisci valori validi.';
          }

          return 'Porte teoriche: ${vlan * ports}.\n'
              'Pianificazione: $vlan VLAN × $ports porte.';
        },
      ),
    ]);
  }

  Widget _fiveGTools() {
    return _page([
      _section(
        '5G / LTE / ARFCN',
        'Calcoli radio e supporto alla verifica dei parametri cellulari.',
      ),
      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'LTE EARFCN → Frequenza',
        icon: Icons.cell_tower_rounded,
        color: orange,
        fields: const ['EARFCN', 'Frequenza base MHz', 'Passo MHz'],
        hints: const ['1650', '1805', '0.1'],
        calculate: (v) {
          final n = _d(v[0]);
          final f0 = _d(v[1]);
          final step = _d(v[2]);

          if (n == null || f0 == null || step == null) {
            return 'Inserisci valori validi.';
          }

          final frequency = f0 + n * step;

          return 'Frequenza stimata: '
              '${frequency.toStringAsFixed(3)} MHz\n'
              'Formula generica: F = Fbase + N × ΔF.\n'
              'Per uso normativo utilizzare i parametri della specifica banda 3GPP.';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: '5G NR-ARFCN → Frequenza',
        icon: Icons.network_cell_rounded,
        color: cyan,
        fields: const ['NR-ARFCN', 'FREF MHz', 'ΔF MHz'],
        hints: const ['620000', '0', '0.005'],
        calculate: (v) {
          final n = _d(v[0]);
          final f = _d(v[1]);
          final d = _d(v[2]);

          if (n == null || f == null || d == null) {
            return 'Inserisci valori validi.';
          }

          final frequency = f + n * d;

          return 'Frequenza: ${frequency.toStringAsFixed(3)} MHz\n'
              'Verificare sempre raster e range della banda NR utilizzata.';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Lunghezza d\'onda',
        icon: Icons.waves_rounded,
        color: green,
        fields: const ['Frequenza MHz'],
        hints: const ['3500'],
        calculate: (v) {
          final mhz = _d(v[0]);

          if (mhz == null || mhz <= 0) {
            return 'Frequenza non valida.';
          }

          final lambda = 299792458 / (mhz * 1000000);

          return 'λ = ${lambda.toStringAsFixed(4)} m\n'
              '≈ ${(lambda * 100).toStringAsFixed(2)} cm';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'RSRP / RSRQ — interpretazione',
        icon: Icons.signal_cellular_alt_rounded,
        color: purple,
        fields: const ['RSRP dBm', 'RSRQ dB'],
        hints: const ['-95', '-10'],
        calculate: (v) {
          final rsrp = _d(v[0]);
          final rsrq = _d(v[1]);

          if (rsrp == null || rsrq == null) {
            return 'Inserisci valori validi.';
          }

          final rsrpText = _signalLevel(rsrp);
          final rsrqText = _rsrqLevel(rsrq);

          return 'RSRP: $rsrp dBm → $rsrpText\n'
              'RSRQ: $rsrq dB → $rsrqText';
        },
      ),
    ]);
  }

  Widget _radioTools() {
    return _page([
      _section(
        'Collegamento radio',
        'Progettazione e diagnostica di collegamenti radio.',
      ),
      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'EIRP',
        icon: Icons.bolt_rounded,
        color: orange,
        fields: const ['TX dBm', 'Guadagno antenna dBi', 'Perdite dB'],
        hints: const ['20', '18', '2'],
        calculate: (v) {
          final tx = _d(v[0]);
          final gain = _d(v[1]);
          final loss = _d(v[2]);

          if (tx == null || gain == null || loss == null) {
            return 'Inserisci valori validi.';
          }

          final eirp = tx + gain - loss;
          final watt = math.pow(10, eirp / 10) / 1000;

          return 'EIRP = ${eirp.toStringAsFixed(2)} dBm\n'
              '≈ ${watt.toStringAsFixed(3)} W';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Perdita in spazio libero',
        icon: Icons.signal_cellular_alt_rounded,
        color: green,
        fields: const ['Distanza km', 'Frequenza GHz'],
        hints: const ['5', '18'],
        calculate: (v) {
          final d = _d(v[0]);
          final f = _d(v[1]);

          if (d == null || f == null || d <= 0 || f <= 0) {
            return 'Inserisci valori validi.';
          }

          final fspl =
              92.45 +
              20 * math.log(d) / math.ln10 +
              20 * math.log(f) / math.ln10;

          return 'FSPL ≈ ${fspl.toStringAsFixed(2)} dB';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Prima zona di Fresnel',
        icon: Icons.radio_rounded,
        color: cyan,
        fields: const ['Distanza totale km', 'Frequenza GHz'],
        hints: const ['10', '18'],
        calculate: (v) {
          final d = _d(v[0]);
          final f = _d(v[1]);

          if (d == null || f == null || d <= 0 || f <= 0) {
            return 'Inserisci valori validi.';
          }

          final radius = 8.657 * math.sqrt(d / f);

          return 'Raggio massimo 1ª zona di Fresnel ≈ '
              '${radius.toStringAsFixed(2)} m\n'
              'Valore riferito al punto centrale del collegamento.';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Bilancio del collegamento',
        icon: Icons.compare_arrows_rounded,
        color: purple,
        fields: const [
          'TX dBm',
          'Guadagno TX dBi',
          'FSPL dB',
          'Guadagno RX dBi',
          'Perdite dB',
          'Sensibilità RX dBm',
        ],
        hints: const ['20', '30', '130', '30', '3', '-70'],
        calculate: (v) {
          final tx = _d(v[0]);
          final gtx = _d(v[1]);
          final fspl = _d(v[2]);
          final grx = _d(v[3]);
          final loss = _d(v[4]);
          final sensitivity = _d(v[5]);

          if ([tx, gtx, fspl, grx, loss, sensitivity].any((x) => x == null)) {
            return 'Inserisci tutti i valori.';
          }

          final rx = tx! + gtx! - fspl! + grx! - loss!;
          final fadeMargin = rx - sensitivity!;

          return 'Potenza RX: ${rx.toStringAsFixed(2)} dBm\n'
              'Margine del collegamento: ${fadeMargin.toStringAsFixed(2)} dB\n'
              '${fadeMargin >= 20 ? 'Collegamento con buon margine.' : 'Verificare il margine del collegamento.'}';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Azimuth punto-punto',
        icon: Icons.explore_rounded,
        color: orange,
        fields: const ['Lat A', 'Lon A', 'Lat B', 'Lon B'],
        hints: const ['41.9028', '12.4964', '45.4642', '9.1900'],
        calculate: (v) {
          final lat1 = _d(v[0]);
          final lon1 = _d(v[1]);
          final lat2 = _d(v[2]);
          final lon2 = _d(v[3]);

          if ([lat1, lon1, lat2, lon2].any((x) => x == null)) {
            return 'Inserisci coordinate valide.';
          }

          final p1 = lat1! * math.pi / 180;
          final p2 = lat2! * math.pi / 180;
          final dlambda = (lon2! - lon1!) * math.pi / 180;

          final y = math.sin(dlambda) * math.cos(p2);
          final x =
              math.cos(p1) * math.sin(p2) -
              math.sin(p1) * math.cos(p2) * math.cos(dlambda);

          var bearing = math.atan2(y, x) * 180 / math.pi;
          bearing = (bearing + 360) % 360;

          return 'Azimuth A → B: ${bearing.toStringAsFixed(2)}°';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Elevazione antenna',
        icon: Icons.height_rounded,
        color: green,
        fields: const ['Distanza km', 'Dislivello m'],
        hints: const ['10', '120'],
        calculate: (v) {
          final d = _d(v[0]);
          final h = _d(v[1]);

          if (d == null || h == null || d <= 0) {
            return 'Inserisci valori validi.';
          }

          final angle = math.atan(h / (d * 1000)) * 180 / math.pi;

          return 'Elevazione geometrica ≈ '
              '${angle.toStringAsFixed(3)}°';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'VSWR / Perdita di ritorno',
        icon: Icons.speed_rounded,
        color: red,
        fields: const ['VSWR'],
        hints: const ['1.20'],
        calculate: (v) {
          final vswr = _d(v[0]);

          if (vswr == null || vswr < 1) {
            return 'VSWR non valido.';
          }

          final gamma = (vswr - 1) / (vswr + 1);
          final rl = gamma == 0
              ? double.infinity
              : -20 * math.log(gamma) / math.ln10;

          final reflection = gamma * gamma * 100;

          return 'Perdita di ritorno ≈ ${rl.toStringAsFixed(2)} dB\n'
              'Potenza riflessa ≈ ${reflection.toStringAsFixed(2)}%';
        },
      ),
    ]);
  }

  Widget _fiberTools() {
    return _page([
      _section(
        'Fibra / GPON / XGS-PON',
        'Budget ottico, attenuazioni e verifica della potenza RX.',
      ),
      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Bilancio ottico',
        icon: Icons.fiber_manual_record_rounded,
        color: cyan,
        fields: const [
          'TX dBm',
          'Fibra km',
          'Attenuazione dB/km',
          'Perdita divisore dB',
          'Connettori/giunzioni dB',
          'Margine dB',
        ],
        hints: const ['3', '10', '0.35', '16', '2', '3'],
        calculate: (v) {
          final tx = _d(v[0]);
          final km = _d(v[1]);
          final att = _d(v[2]);
          final split = _d(v[3]);
          final conn = _d(v[4]);
          final margin = _d(v[5]);

          if ([tx, km, att, split, conn, margin].any((x) => x == null)) {
            return 'Inserisci tutti i valori.';
          }

          final fiberLoss = km! * att!;
          final totalLoss = fiberLoss + split! + conn!;
          final rx = tx! - totalLoss;
          final rxWithMargin = rx - margin!;

          return 'Perdita fibra: ${fiberLoss.toStringAsFixed(2)} dB\n'
              'Perdita totale: ${totalLoss.toStringAsFixed(2)} dB\n'
              'RX stimata: ${rx.toStringAsFixed(2)} dBm\n'
              'RX dopo margine: ${rxWithMargin.toStringAsFixed(2)} dBm';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'GPON / XGS-PON — verifica RX',
        icon: Icons.check_circle_outline_rounded,
        color: green,
        fields: const ['Potenza RX dBm', 'Sensibilità ONU/ONT dBm'],
        hints: const ['-24', '-28'],
        calculate: (v) {
          final rx = _d(v[0]);
          final sens = _d(v[1]);

          if (rx == null || sens == null) {
            return 'Inserisci valori validi.';
          }

          final margin = rx - sens;

          return margin >= 0
              ? 'OK — margine disponibile: '
                    '${margin.toStringAsFixed(2)} dB'
              : 'ATTENZIONE — fuori budget di '
                    '${(-margin).toStringAsFixed(2)} dB';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Attenuazione fibra',
        icon: Icons.timeline_rounded,
        color: orange,
        fields: [
          'Lunghezza km',
          'Attenuazione dB/km',
          'Numero connettori',
          'Perdita per connettore dB',
          'Numero giunzioni',
          'Perdita per giunzione dB',
        ],
        hints: const ['8', '0.35', '4', '0.3', '2', '0.1'],
        calculate: (v) {
          final km = _d(v[0]);
          final att = _d(v[1]);
          final connectors = _d(v[2]);
          final connectorLoss = _d(v[3]);
          final splices = _d(v[4]);
          final spliceLoss = _d(v[5]);

          if ([
            km,
            att,
            connectors,
            connectorLoss,
            splices,
            spliceLoss,
          ].any((x) => x == null)) {
            return 'Inserisci tutti i valori.';
          }

          final total =
              km! * att! +
              connectors! * connectorLoss! +
              splices! * spliceLoss!;

          return 'Attenuazione totale ≈ '
              '${total.toStringAsFixed(2)} dB';
        },
      ),
    ]);
  }

  Widget _maintenanceTools() {
    return _page([
      _section(
        'Manutenzione stazioni radio',
        'Strumenti pratici per attività preventive e ricerca guasti.',
      ),
      const SizedBox(height: 12),

      _maintenanceOverview(),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'PIM — livello relativo',
        icon: Icons.warning_amber_rounded,
        color: red,
        fields: const ['PIM misurato dBm', 'Limite apparato dBm'],
        hints: const ['-110', '-100'],
        calculate: (v) {
          final measured = _d(v[0]);
          final limit = _d(v[1]);

          if (measured == null || limit == null) {
            return 'Inserisci valori validi.';
          }

          final delta = measured - limit;

          return 'PIM misurato: ${measured.toStringAsFixed(1)} dBm\n'
              'Limite: ${limit.toStringAsFixed(1)} dBm\n'
              'Scostamento: ${delta.toStringAsFixed(1)} dB\n'
              '${delta <= 0 ? 'OK — sotto il limite.' : 'ATTENZIONE — sopra il limite.'}';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'VSWR / Perdita di ritorno',
        icon: Icons.speed_rounded,
        color: orange,
        fields: const ['VSWR'],
        hints: const ['1.20'],
        calculate: (v) {
          final vswr = _d(v[0]);

          if (vswr == null || vswr < 1) {
            return 'VSWR non valido.';
          }

          final gamma = (vswr - 1) / (vswr + 1);
          final rl = gamma == 0 ? 999 : -20 * math.log(gamma) / math.ln10;

          final reflected = gamma * gamma * 100;

          String status;

          if (vswr <= 1.3) {
            status = 'Ottimo.';
          } else if (vswr <= 1.5) {
            status = 'Buono.';
          } else if (vswr <= 2) {
            status = 'Da verificare.';
          } else {
            status = 'Critico — verificare linea/antenna.';
          }

          return 'VSWR: ${vswr.toStringAsFixed(2)}\n'
              'Perdita di ritorno: ${rl.toStringAsFixed(2)} dB\n'
              'Potenza riflessa: ${reflected.toStringAsFixed(2)}%\n'
              'Stato: $status';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Temperatura apparato',
        icon: Icons.thermostat_rounded,
        color: red,
        fields: ['Temperatura °C', 'Soglia attenzione °C', 'Soglia critica °C'],
        hints: const ['45', '60', '70'],
        calculate: (v) {
          final temp = _d(v[0]);
          final warning = _d(v[1]);
          final critical = _d(v[2]);

          if ([temp, warning, critical].any((x) => x == null)) {
            return 'Inserisci tutti i valori.';
          }

          if (temp! >= critical!) {
            return 'CRITICO — ${temp.toStringAsFixed(1)} °C';
          }

          if (temp >= warning!) {
            return 'ATTENZIONE — ${temp.toStringAsFixed(1)} °C';
          }

          return 'OK — ${temp.toStringAsFixed(1)} °C';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Margine del collegamento radio',
        icon: Icons.cloud_queue_rounded,
        color: purple,
        fields: ['Potenza RX dBm', 'Sensibilità RX dBm'],
        hints: const ['-55', '-75'],
        calculate: (v) {
          final rx = _d(v[0]);
          final sensitivity = _d(v[1]);

          if (rx == null || sensitivity == null) {
            return 'Inserisci valori validi.';
          }

          final margin = rx - sensitivity;

          String status;

          if (margin >= 30) {
            status = 'Ottimo';
          } else if (margin >= 20) {
            status = 'Buono';
          } else if (margin >= 10) {
            status = 'Margine ridotto';
          } else {
            status = 'Critico';
          }

          return 'Margine del collegamento: ${margin.toStringAsFixed(2)} dB\n'
              'Valutazione: $status';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Batteria / autonomia',
        icon: Icons.battery_full_rounded,
        color: green,
        fields: [
          'Capacità batteria Ah',
          'Tensione V',
          'Carico W',
          'Efficienza sistema %',
          'Utilizzo batteria %',
        ],
        hints: const ['200', '48', '500', '90', '80'],
        calculate: (v) {
          final ah = _d(v[0]);
          final voltage = _d(v[1]);
          final load = _d(v[2]);
          final efficiency = _d(v[3]);
          final usable = _d(v[4]);

          if ([ah, voltage, load, efficiency, usable].any((x) => x == null)) {
            return 'Inserisci tutti i valori.';
          }

          if (load! <= 0 ||
              efficiency! <= 0 ||
              efficiency > 100 ||
              usable! <= 0 ||
              usable > 100) {
            return 'Parametri non validi.';
          }

          final energyWh = ah! * voltage! * (usable / 100);
          final autonomy = energyWh * (efficiency / 100) / load;

          return 'Energia utilizzabile: '
              '${energyWh.toStringAsFixed(0)} Wh\n'
              'Autonomia teorica: '
              '${autonomy.toStringAsFixed(2)} h';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Messa a terra — caduta di tensione',
        icon: Icons.electrical_services_rounded,
        color: cyan,
        fields: ['Corrente A', 'Resistenza terra Ω'],
        hints: const ['10', '0.5'],
        calculate: (v) {
          final current = _d(v[0]);
          final resistance = _d(v[1]);

          if (current == null ||
              resistance == null ||
              current < 0 ||
              resistance < 0) {
            return 'Inserisci valori validi.';
          }

          final voltage = current * resistance;
          final power = current * current * resistance;

          return 'Caduta V = ${voltage.toStringAsFixed(2)} V\n'
              'Potenza dissipata = ${power.toStringAsFixed(2)} W\n'
              'Confrontare con i limiti del sistema di terra.';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Connettori / jumper — perdita',
        icon: Icons.cable_rounded,
        color: orange,
        fields: [
          'Numero jumper',
          'Perdita per jumper dB',
          'Numero connettori',
          'Perdita per connettore dB',
        ],
        hints: const ['2', '0.3', '4', '0.2'],
        calculate: (v) {
          final jumpers = _d(v[0]);
          final jumperLoss = _d(v[1]);
          final connectors = _d(v[2]);
          final connectorLoss = _d(v[3]);

          if ([
            jumpers,
            jumperLoss,
            connectors,
            connectorLoss,
          ].any((x) => x == null)) {
            return 'Inserisci tutti i valori.';
          }

          final total = jumpers! * jumperLoss! + connectors! * connectorLoss!;

          return 'Perdita totale stimata: '
              '${total.toStringAsFixed(2)} dB';
        },
      ),
    ]);
  }

  Widget _maintenanceOverview() {
    final items = [
      ('Antenna', Icons.cell_tower_rounded),
      ('RRU/RRH', Icons.settings_input_antenna_rounded),
      ('Feeder', Icons.cable_rounded),
      ('PIM', Icons.warning_amber_rounded),
      ('VSWR', Icons.speed_rounded),
      ('Messa a terra', Icons.electrical_services_rounded),
      ('Batterie', Icons.battery_full_rounded),
      ('Shelter', Icons.home_work_rounded),
    ];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Controlli principali',
            style: TextStyle(
              color: text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 13),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
            ),
            itemBuilder: (_, i) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: card2,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(items[i].$2, size: 17, color: cyan),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        items[i].$1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: text,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _energyTools() {
    return _page([
      _section(
        'Energia / DC / UPS',
        'Dimensionamento rapido di consumi e autonomia.',
      ),
      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Potenza DC',
        icon: Icons.power_rounded,
        color: green,
        fields: ['Tensione V', 'Corrente A'],
        hints: const ['48', '10'],
        calculate: (v) {
          final voltage = _d(v[0]);
          final current = _d(v[1]);

          if (voltage == null || current == null) {
            return 'Inserisci valori validi.';
          }

          final power = voltage * current;

          return 'Potenza DC = ${power.toStringAsFixed(2)} W\n'
              '≈ ${(power / 1000).toStringAsFixed(3)} kW';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Consumo energetico',
        icon: Icons.electric_meter_rounded,
        color: cyan,
        fields: ['Potenza W', 'Ore/giorno', 'Giorni'],
        hints: const ['500', '24', '30'],
        calculate: (v) {
          final power = _d(v[0]);
          final hours = _d(v[1]);
          final days = _d(v[2]);

          if (power == null || hours == null || days == null) {
            return 'Inserisci valori validi.';
          }

          final kwh = power * hours * days / 1000;

          return 'Consumo: ${kwh.toStringAsFixed(2)} kWh';
        },
      ),

      const SizedBox(height: 12),

      _SimpleCalculatorCard(
        title: 'Autonomia UPS',
        icon: Icons.battery_charging_full_rounded,
        color: orange,
        fields: ['Energia batteria Wh', 'Carico W', 'Efficienza %'],
        hints: const ['9600', '500', '90'],
        calculate: (v) {
          final energy = _d(v[0]);
          final load = _d(v[1]);
          final efficiency = _d(v[2]);

          if (energy == null ||
              load == null ||
              efficiency == null ||
              load <= 0) {
            return 'Parametri non validi.';
          }

          final hours = energy * (efficiency / 100) / load;

          return 'Autonomia teorica: '
              '${hours.toStringAsFixed(2)} h\n'
              '≈ ${(hours * 60).toStringAsFixed(0)} minuti';
        },
      ),
    ]);
  }

  Widget _checklistTools() {
    return _page([
      _section(
        'Controlli di manutenzione',
        'Controlli rapidi prima, durante e dopo l\'intervento.',
      ),
      const SizedBox(height: 12),
      const _MaintenanceChecklistCard(),
    ]);
  }

  Widget _reportTools() {
    return _page([
      _section(
        'Report tecnico',
        'Genera un riepilogo testuale copiabile e condivisibile.',
      ),
      const SizedBox(height: 12),
      const _ReportCard(),
    ]);
  }

  double? _d(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  String _signalLevel(double value) {
    if (value >= -80) return 'Eccellente';
    if (value >= -90) return 'Buono';
    if (value >= -100) return 'Discreto';
    if (value >= -110) return 'Debole';
    return 'Molto debole';
  }

  String _rsrqLevel(double value) {
    if (value >= -10) return 'Ottimo';
    if (value >= -15) return 'Buono';
    if (value >= -20) return 'Debole';
    return 'Critico';
  }

  Widget _hero(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: text,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: text,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _infoCard(String title, String body, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelcoTab {
  final String label;
  final IconData icon;

  const _TelcoTab(this.label, this.icon);
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _SimpleCalculatorCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> fields;
  final List<String> hints;
  final String Function(List<String>) calculate;

  const _SimpleCalculatorCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.fields,
    required this.hints,
    required this.calculate,
  });

  @override
  State<_SimpleCalculatorCard> createState() => _SimpleCalculatorCardState();
}

class _SimpleCalculatorCardState extends State<_SimpleCalculatorCard> {
  late final List<TextEditingController> _controllers;
  String _result = '';

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(
      widget.fields.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _calculate() {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _result = widget.calculate(
        _controllers.map((controller) => controller.text.trim()).toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _TelcoToolsScreenState.card,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TelcoToolsScreenState.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ...List.generate(widget.fields.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _controllers[i],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                textInputAction: i == widget.fields.length - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                onSubmitted: (_) {
                  if (i == widget.fields.length - 1) {
                    _calculate();
                  }
                },
                style: const TextStyle(
                  color: _TelcoToolsScreenState.text,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  labelText: widget.fields[i],
                  hintText: widget.hints.length > i ? widget.hints[i] : null,
                  labelStyle: const TextStyle(
                    color: _TelcoToolsScreenState.muted,
                  ),
                  hintStyle: const TextStyle(
                    color: _TelcoToolsScreenState.muted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  filled: true,
                  fillColor: _TelcoToolsScreenState.card2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.color, width: 1.2),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 2),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate_rounded, size: 18),
              label: const Text(
                'CALCOLA',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.color,
                foregroundColor: _TelcoToolsScreenState.bg,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          if (_result.isNotEmpty) ...[
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.color.withValues(alpha: .25)),
              ),
              child: SelectableText(
                _result,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubnetCard extends StatefulWidget {
  @override
  State<_SubnetCard> createState() => _SubnetCardState();
}

class _SubnetCardState extends State<_SubnetCard> {
  final _controller = TextEditingController(text: '192.168.1.0/24');

  String _result = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final parts = _controller.text.trim().split('/');

      if (parts.length != 2) {
        throw Exception();
      }

      final octets = parts[0].split('.').map(int.parse).toList();

      final prefix = int.parse(parts[1]);

      if (octets.length != 4 ||
          prefix < 0 ||
          prefix > 32 ||
          octets.any((x) => x < 0 || x > 255)) {
        throw Exception();
      }

      final ip =
          (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];

      final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;

      final network = ip & mask;
      final broadcast = network | (~mask & 0xFFFFFFFF);

      final total = math.pow(2, 32 - prefix).toInt();

      final usable = prefix >= 31 ? total : math.max(0, total - 2);

      setState(() {
        _result =
            'Rete: ${_ip(network)}\n'
            'Broadcast: ${_ip(broadcast)}\n'
            'Mask: ${_ip(mask)} /$prefix\n'
            'Indirizzi: $total\n'
            'Host utilizzabili: $usable\n'
            'First host: ${prefix >= 31 ? '-' : _ip(network + 1)}\n'
            'Last host: ${prefix >= 31 ? '-' : _ip(broadcast - 1)}';
      });
    } catch (_) {
      setState(() {
        _result = 'CIDR non valido.';
      });
    }
  }

  String _ip(int x) =>
      '${(x >> 24) & 255}.'
      '${(x >> 16) & 255}.'
      '${(x >> 8) & 255}.'
      '${x & 255}';

  @override
  Widget build(BuildContext context) {
    return _box(
      'CIDR / Subnet Calculator',
      Icons.lan_rounded,
      _TelcoToolsScreenState.cyan,
      [
        _input(_controller, 'IPv4/CIDR'),
        const SizedBox(height: 10),
        _button('CALCOLA SUBNET', _TelcoToolsScreenState.cyan, _calculate),
        if (_result.isNotEmpty)
          _resultBox(_result, _TelcoToolsScreenState.cyan),
      ],
    );
  }
}

class _Ipv6Card extends StatefulWidget {
  @override
  State<_Ipv6Card> createState() => _Ipv6CardState();
}

class _Ipv6CardState extends State<_Ipv6Card> {
  final _controller = TextEditingController(text: '2001:db8::/64');

  String _result = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculate() {
    final value = _controller.text.trim();
    final parts = value.split('/');

    final prefix = parts.length == 2 ? int.tryParse(parts[1]) : null;

    final address = parts.isNotEmpty ? parts[0] : '';

    if (prefix == null ||
        prefix < 0 ||
        prefix > 128 ||
        address.isEmpty ||
        !address.contains(':')) {
      setState(() {
        _result = 'IPv6/prefix non valido.';
      });
      return;
    }

    final hostBits = 128 - prefix;

    final subnets64 = prefix <= 64
        ? '2^${64 - prefix} subnet /64'
        : 'prefix più specifico di /64';

    setState(() {
      _result =
          'Prefix: /$prefix\n'
          'Host bits: $hostBits\n'
          'Indirizzi teorici: 2^$hostBits\n'
          'Piano /64: $subnets64\n'
          'Prefisso: $address/$prefix';
    });
  }

  @override
  Widget build(BuildContext context) {
    return _box(
      'IPv6 Prefix Helper',
      Icons.public_rounded,
      _TelcoToolsScreenState.green,
      [
        _input(_controller, 'IPv6/prefix'),
        const SizedBox(height: 10),
        _button('ANALIZZA', _TelcoToolsScreenState.green, _calculate),
        if (_result.isNotEmpty)
          _resultBox(_result, _TelcoToolsScreenState.green),
      ],
    );
  }
}

class _VlsmCard extends StatefulWidget {
  @override
  State<_VlsmCard> createState() => _VlsmCardState();
}

class _VlsmCardState extends State<_VlsmCard> {
  final _base = TextEditingController(text: '192.168.10.0/24');

  final _hosts = TextEditingController(text: '50, 20, 10');

  String _result = '';

  @override
  void dispose() {
    _base.dispose();
    _hosts.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final parts = _base.text.trim().split('/');

      final octets = parts[0].split('.').map(int.parse).toList();

      final prefix = int.parse(parts[1]);

      final requests =
          _hosts.text
              .split(',')
              .map((e) => int.parse(e.trim()))
              .where((e) => e > 0)
              .toList()
            ..sort((a, b) => b.compareTo(a));

      if (octets.length != 4 || prefix < 0 || prefix > 30 || requests.isEmpty) {
        throw Exception();
      }

      int network =
          (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];

      final capacity = math.pow(2, 32 - prefix).toInt();

      final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;

      final baseNetwork = network & mask;

      network = baseNetwork;

      final end = baseNetwork + capacity;
      final lines = <String>[];

      for (final hosts in requests) {
        final needed = hosts + 2;

        int block = 1;

        while (block < needed) {
          block *= 2;
        }

        final newPrefix = 32 - (math.log(block) / math.ln2).round();

        if (network + block > end) {
          throw Exception();
        }

        final broadcast = network + block - 1;

        lines.add(
          '$hosts host → '
          '${_ip(network)}/$newPrefix '
          '(${_ip(network + 1)}–'
          '${_ip(broadcast - 1)})',
        );

        network += block;
      }

      setState(() {
        _result = lines.join('\n');
      });
    } catch (_) {
      setState(() {
        _result = 'Impossibile creare il piano VLSM con i dati inseriti.';
      });
    }
  }

  String _ip(int x) =>
      '${(x >> 24) & 255}.'
      '${(x >> 16) & 255}.'
      '${(x >> 8) & 255}.'
      '${x & 255}';

  @override
  Widget build(BuildContext context) {
    return _box(
      'Pianificatore VLSM',
      Icons.account_tree_rounded,
      _TelcoToolsScreenState.orange,
      [
        _input(_base, 'Rete base CIDR'),
        const SizedBox(height: 10),
        _input(_hosts, 'Host richiesti, separati da virgola'),
        const SizedBox(height: 10),
        _button('PIANIFICA VLSM', _TelcoToolsScreenState.orange, _calculate),
        if (_result.isNotEmpty)
          _resultBox(_result, _TelcoToolsScreenState.orange),
      ],
    );
  }
}

class _MaintenanceChecklistCard extends StatefulWidget {
  const _MaintenanceChecklistCard();

  @override
  State<_MaintenanceChecklistCard> createState() =>
      _MaintenanceChecklistCardState();
}

class _MaintenanceChecklistCardState extends State<_MaintenanceChecklistCard> {
  final Map<String, bool> _checks = {
    'Accesso sito / sicurezza area': false,
    'Controllo stato shelter/cabinet': false,
    'Alimentazione AC/DC': false,
    'Batterie / UPS': false,
    'Ventole / climatizzazione': false,
    'Messa a terra / equipotenzialità': false,
    'Controllo allarmi apparati': false,
    'RRU/RRH / radio unit': false,
    'Cavi RF / jumper': false,
    'Connettori RF': false,
    'VSWR / Perdita di ritorno': false,
    'PIM': false,
    'Antenne e radome': false,
    'Orientamento / azimuth': false,
    'Fibra ottica': false,
    'Potenza ottica RX': false,
    'Link microwave': false,
    'Livelli RX/TX': false,
    'Documentazione fotografica': false,
    'Chiusura attività / report': false,
  };

  @override
  Widget build(BuildContext context) {
    final completed = _checks.values.where((x) => x).length;

    final total = _checks.length;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _TelcoToolsScreenState.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_rounded,
                color: _TelcoToolsScreenState.purple,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Lista di controllo intervento',
                  style: TextStyle(
                    color: _TelcoToolsScreenState.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$completed/$total',
                style: const TextStyle(
                  color: _TelcoToolsScreenState.purple,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : completed / total,
              minHeight: 6,
              backgroundColor: _TelcoToolsScreenState.card2,
              valueColor: const AlwaysStoppedAnimation<Color>(
                _TelcoToolsScreenState.purple,
              ),
            ),
          ),

          const SizedBox(height: 12),

          ..._checks.entries.map((entry) {
            return Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                value: entry.value,
                onChanged: (value) {
                  setState(() {
                    _checks[entry.key] = value ?? false;
                  });
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: _TelcoToolsScreenState.purple,
                checkColor: _TelcoToolsScreenState.bg,
                title: Text(
                  entry.key,
                  style: const TextStyle(
                    color: _TelcoToolsScreenState.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  for (final key in _checks.keys) {
                    _checks[key] = false;
                  }
                });
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text(
                'AZZERA CHECKLIST',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _TelcoToolsScreenState.muted,
                side: BorderSide(color: Colors.white.withValues(alpha: .12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  const _ReportCard();

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final _site = TextEditingController();
  final _operator = TextEditingController();
  final _technology = TextEditingController();
  final _equipment = TextEditingController();
  final _notes = TextEditingController();

  String _report = '';

  @override
  void dispose() {
    _site.dispose();
    _operator.dispose();
    _technology.dispose();
    _equipment.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _generate() {
    FocusManager.instance.primaryFocus?.unfocus();

    final now = DateTime.now();

    setState(() {
      _report =
          '''
REPORT TECNICO TELCO
====================

Data:
${now.day.toString().padLeft(2, '0')}/
${now.month.toString().padLeft(2, '0')}/
${now.year}

SITO / CLIENTE
${_site.text}

TECNICO / OPERATORE
${_operator.text}

TECNOLOGIA
${_technology.text}

APPARATO / SISTEMA
${_equipment.text}

NOTE TECNICHE
${_notes.text}

CHECK GENERALI
- Alimentazione verificata
- Messa a terra verificato
- Allarmi verificati
- RF verificato
- Fibra verificata
- Documentazione aggiornata

--- FINE REPORT ---
''';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _TelcoToolsScreenState.card,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Column(
        children: [
          _field(_site, 'Sito / Cliente'),
          const SizedBox(height: 10),
          _field(_operator, 'Tecnico / Operatore'),
          const SizedBox(height: 10),
          _field(_technology, 'Tecnologia'),
          const SizedBox(height: 10),
          _field(_equipment, 'Apparato / Sistema'),
          const SizedBox(height: 10),
          _field(_notes, 'Note tecniche', maxLines: 6),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.description_rounded),
              label: const Text(
                'GENERA REPORT',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _TelcoToolsScreenState.green,
                foregroundColor: _TelcoToolsScreenState.bg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          if (_report.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _TelcoToolsScreenState.card2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _report,
                style: const TextStyle(
                  color: _TelcoToolsScreenState.text,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: _TelcoToolsScreenState.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _TelcoToolsScreenState.muted),
        filled: true,
        fillColor: _TelcoToolsScreenState.card2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _TelcoToolsScreenState.green),
        ),
      ),
    );
  }
}

Widget _box(String title, IconData icon, Color color, List<Widget> children) {
  return Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: _TelcoToolsScreenState.card,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: Colors.white.withValues(alpha: .055)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _TelcoToolsScreenState.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

Widget _input(TextEditingController controller, String hint) {
  return TextField(
    controller: controller,
    style: const TextStyle(color: _TelcoToolsScreenState.text, fontSize: 14),
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _TelcoToolsScreenState.muted),
      filled: true,
      fillColor: _TelcoToolsScreenState.card2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TelcoToolsScreenState.cyan),
      ),
    ),
  );
}

Widget _button(String label, Color color, VoidCallback onTap) {
  return SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calculate_rounded, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: _TelcoToolsScreenState.bg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

Widget _resultBox(String value, Color color) {
  return Padding(
    padding: const EdgeInsets.only(top: 13),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.5,
        ),
      ),
    ),
  );
}
