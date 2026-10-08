import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color panel = Color(0xFF191A24);
  static const Color button = Color(0xFF20212B);
  static const Color buttonLight = Color(0xFF292A34);

  static const Color cyan = Color(0xFFE6E6E6);
  static const Color textSecondary = Color(0xFFAAAAB4);
  static const Color danger = Color(0xFFFF5570);
  static const Color orange = Color(0xFFFFB547);

  // ============================================================
  // STATE
  // ============================================================

  String _expression = '';
  String _result = '0';

  bool _scientific = false;
  bool _degrees = true;

  double _memory = 0;

  final List<String> _history = [];

  // ============================================================
  // BASIC BUTTONS
  // ============================================================

  final List<String> _basicButtons = [
    'AC',
    '⌫',
    '%',
    '÷',
    '7',
    '8',
    '9',
    '×',
    '4',
    '5',
    '6',
    '−',
    '1',
    '2',
    '3',
    '+',
    '±',
    '0',
    ',',
    'π',
    '(',
    ')',
    '=',
  ];

  // ============================================================
  // SCIENTIFIC FUNCTION ROWS
  // ============================================================

  final List<List<String>> _scientificFunctionRows = [
    ['sin', 'cos', 'tan', '√'],
    ['sin⁻¹', 'cos⁻¹', 'tan⁻¹', 'x²'],
    ['ln', 'log', 'xʸ', '1/x'],
    ['π', 'e', '(', ')'],
  ];

  // ============================================================
  // PRESS BUTTON
  // ============================================================

  void _press(String value) {
    if (value == 'AC') {
      _clear();
      return;
    }

    if (value == '⌫') {
      _backspace();
      return;
    }

    if (value == '=') {
      _calculate();
      return;
    }

    if (value == '±') {
      _toggleSign();
      return;
    }

    if (value == 'sin' ||
        value == 'cos' ||
        value == 'tan' ||
        value == 'sin⁻¹' ||
        value == 'cos⁻¹' ||
        value == 'tan⁻¹' ||
        value == '√' ||
        value == 'ln' ||
        value == 'log') {
      _addFunction(value);
      return;
    }

    if (value == 'x²') {
      _addPower('2');
      return;
    }

    if (value == 'xʸ') {
      if (_expression.isEmpty) return;

      setState(() {
        _expression += '^';
      });

      return;
    }

    if (value == '1/x') {
      if (_expression.isEmpty) return;

      setState(() {
        _expression = '1/($_expression)';
      });

      return;
    }

    if (value == ',') {
      setState(() {
        _expression += '.';
      });

      return;
    }

    setState(() {
      _expression += value;
    });
  }

  // ============================================================
  // CLEAR
  // ============================================================

  void _clear() {
    setState(() {
      _expression = '';
      _result = '0';
    });
  }

  // ============================================================
  // BACKSPACE
  // ============================================================

  void _backspace() {
    if (_expression.isEmpty) return;

    setState(() {
      _expression = _expression.substring(0, _expression.length - 1);
    });
  }

  // ============================================================
  // PLUS / MINUS
  // ============================================================

  void _toggleSign() {
    if (_expression.isEmpty) return;

    setState(() {
      if (_expression.startsWith('-(') && _expression.endsWith(')')) {
        _expression = _expression.substring(2, _expression.length - 1);
      } else {
        _expression = '-($_expression)';
      }
    });
  }

  // ============================================================
  // SCIENTIFIC FUNCTION
  // ============================================================

  void _addFunction(String function) {
    String value;

    switch (function) {
      case 'sin':
        value = 'sin(';
        break;

      case 'cos':
        value = 'cos(';
        break;

      case 'tan':
        value = 'tan(';
        break;

      case 'sin⁻¹':
        value = 'asin(';
        break;

      case 'cos⁻¹':
        value = 'acos(';
        break;

      case 'tan⁻¹':
        value = 'atan(';
        break;

      case '√':
        value = 'sqrt(';
        break;

      case 'ln':
        value = 'ln(';
        break;

      case 'log':
        value = 'log(';
        break;

      default:
        return;
    }

    setState(() {
      _expression += value;
    });
  }

  // ============================================================
  // POWER
  // ============================================================

  void _addPower(String power) {
    if (_expression.isEmpty) return;

    setState(() {
      _expression = '($_expression)^$power';
    });
  }

  // ============================================================
  // NORMALIZE EXPRESSION
  // ============================================================

  String _normalizeExpression(String expression) {
    String result = expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll('π', 'pi');

    // Percentuali semplici.
    result = result.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)%'), (match) {
      return '(${match.group(1)}/100)';
    });

    return result;
  }

  // ============================================================
  // CALCULATE
  // ============================================================

  void _calculate() {
    if (_expression.trim().isEmpty) return;

    try {
      final expression = _normalizeExpression(_expression);

      final parser = ShuntingYardParser();

      final parsed = parser.parse(expression);

      final evaluator = _ScientificEvaluator(degrees: _degrees);

      // math_expressions restituisce num.
      // toDouble() evita l'errore num -> double.
      final double value = evaluator.evaluate(parsed);

      if (!value.isFinite || value.isNaN) {
        throw Exception();
      }

      final formatted = _format(value);

      setState(() {
        _history.insert(0, '$_expression = $formatted');

        if (_history.length > 20) {
          _history.removeLast();
        }

        _result = formatted;
      });
    } catch (_) {
      setState(() {
        _result = 'Errore';
      });
    }
  }

  // ============================================================
  // FORMAT NUMBER
  // ============================================================

  String _format(double value) {
    if ((value - value.roundToDouble()).abs() < 0.0000000001) {
      return value.toInt().toString();
    }

    String result = value.toStringAsFixed(10);

    result = result.replaceFirst(RegExp(r'0+$'), '');

    result = result.replaceFirst(RegExp(r'\.$'), '');

    return result;
  }

  // ============================================================
  // MEMORY
  // ============================================================

  void _memoryClear() {
    setState(() {
      _memory = 0;
    });
  }

  void _memoryRecall() {
    setState(() {
      _expression += _format(_memory);
    });
  }

  void _memoryAdd() {
    final value = _currentValue();

    if (value != null) {
      setState(() {
        _memory += value;
      });
    }
  }

  void _memorySubtract() {
    final value = _currentValue();

    if (value != null) {
      setState(() {
        _memory -= value;
      });
    }
  }

  double? _currentValue() {
    try {
      final expression = _normalizeExpression(_expression);

      final parser = ShuntingYardParser();

      final parsed = parser.parse(expression);

      final evaluator = _ScientificEvaluator(degrees: _degrees);

      return evaluator.evaluate(parsed);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // HISTORY
  // ============================================================

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Cronologia',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);

                          setState(() {
                            _history.clear();
                          });
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: danger,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: _history.isEmpty
                        ? const Center(
                            child: Text(
                              'Nessun calcolo effettuato',
                              style: TextStyle(color: textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _history.length,
                            separatorBuilder: (_, _) =>
                                const Divider(color: Colors.white10),
                            itemBuilder: (_, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Text(
                                  _history[index],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),

        title: const Text(
          'Calcolatrice',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),

        actions: [
          IconButton(
            tooltip: 'Cronologia',
            onPressed: _showHistory,
            icon: const Icon(Icons.history_rounded, color: textSecondary),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            // ==================================================
            // MODE SELECTOR
            // ==================================================
            _buildModeSelector(),

            // ==================================================
            // DISPLAY + MEMORY
            // ==================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Column(
                children: [
                  _buildDisplay(),

                  const SizedBox(height: 8),

                  _buildMemoryBar(),

                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ==================================================
            // SCROLL SOLO DELLA TASTIERA
            // ==================================================
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                child: _scientific
                    ? _buildScientificKeyboard()
                    : _buildBasicKeyboard(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MODE SELECTOR
  // ============================================================

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: _modeButton(
              title: 'BASE',
              selected: !_scientific,
              onTap: () {
                setState(() {
                  _scientific = false;
                });
              },
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: _modeButton(
              title: 'SCIENTIFICA',
              selected: _scientific,
              onTap: () {
                setState(() {
                  _scientific = true;
                });
              },
            ),
          ),

          const SizedBox(width: 8),

          _angleButton(),
        ],
      ),
    );
  }

  // ============================================================
  // MODE BUTTON
  // ============================================================

  Widget _modeButton({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),

        height: 38,

        decoration: BoxDecoration(
          color: selected ? cyan.withValues(alpha: 0.12) : panel,

          borderRadius: BorderRadius.circular(12),

          border: Border.all(
            color: selected
                ? cyan.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),

        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: selected ? cyan : textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DEG / RAD
  // ============================================================

  Widget _angleButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _degrees = !_degrees;
        });
      },

      child: Container(
        height: 38,
        width: 60,

        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),

        child: Center(
          child: Text(
            _degrees ? 'DEG' : 'RAD',
            style: const TextStyle(
              color: orange,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DISPLAY
  // ============================================================

  Widget _buildDisplay() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),

      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              const Icon(Icons.functions_rounded, color: cyan, size: 16),

              const SizedBox(width: 7),

              Text(
                _scientific ? 'SCIENTIFICA' : 'CALCOLO',
                style: const TextStyle(
                  color: cyan,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),

              const Spacer(),

              Text(
                _degrees ? 'DEG' : 'RAD',
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: Text(
              _expression.isEmpty ? '0' : _expression,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: textSecondary, fontSize: 16),
            ),
          ),

          const SizedBox(height: 2),

          SizedBox(
            height: 46,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _result,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MEMORY BAR
  // ============================================================

  Widget _buildMemoryBar() {
    return Container(
      height: 36,

      padding: const EdgeInsets.symmetric(horizontal: 4),

      decoration: BoxDecoration(
        color: panel,

        borderRadius: BorderRadius.circular(11),

        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),

      child: Row(
        children: [
          _memoryButton('MC', _memoryClear),

          _memoryButton('MR', _memoryRecall),

          _memoryButton('M+', _memoryAdd),

          _memoryButton('M−', _memorySubtract),

          const Spacer(),

          if (_memory != 0)
            Text(
              'M ${_format(_memory)}',
              style: const TextStyle(
                color: orange,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),

          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ============================================================
  // MEMORY BUTTON
  // ============================================================

  Widget _memoryButton(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(8),

        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BASIC KEYBOARD
  // ============================================================

  Widget _buildBasicKeyboard() {
    return GridView.builder(
      shrinkWrap: true,

      physics: const NeverScrollableScrollPhysics(),

      itemCount: _basicButtons.length,

      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        childAspectRatio: 1.35,
      ),

      itemBuilder: (_, index) {
        return _buildKey(_basicButtons[index]);
      },
    );
  }

  // ============================================================
  // SCIENTIFIC KEYBOARD
  //
  // La parte scientifica è separata dalla parte numerica.
  //
  // Questo mantiene SEMPRE:
  //
  // 7 8 9 ÷
  // 4 5 6 ×
  // 1 2 3 −
  // ± 0 , +
  //
  // e poi:
  //
  // AC ⌫ % =
  // ============================================================

  Widget _buildScientificKeyboard() {
    return Column(
      children: [
        // ======================================================
        // SCIENTIFIC FUNCTIONS
        // ======================================================
        for (final row in _scientificFunctionRows)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),

            child: Row(
              children: [
                for (int i = 0; i < row.length; i++) ...[
                  Expanded(
                    child: SizedBox(height: 58, child: _buildKey(row[i])),
                  ),

                  if (i < row.length - 1) const SizedBox(width: 7),
                ],
              ],
            ),
          ),

        const SizedBox(height: 2),

        // ======================================================
        // NUMERIC SECTION
        // ======================================================
        GridView.count(
          shrinkWrap: true,

          physics: const NeverScrollableScrollPhysics(),

          crossAxisCount: 4,

          crossAxisSpacing: 7,
          mainAxisSpacing: 7,

          childAspectRatio: 1.35,

          children: [
            // 7 8 9 ÷
            _buildKey('7'),
            _buildKey('8'),
            _buildKey('9'),
            _buildKey('÷'),

            // 4 5 6 ×
            _buildKey('4'),
            _buildKey('5'),
            _buildKey('6'),
            _buildKey('×'),

            // 1 2 3 −
            _buildKey('1'),
            _buildKey('2'),
            _buildKey('3'),
            _buildKey('−'),

            // ± 0 , +
            _buildKey('±'),
            _buildKey('0'),
            _buildKey(','),
            _buildKey('+'),

            // AC ⌫ % =
            _buildKey('AC'),
            _buildKey('⌫'),
            _buildKey('%'),
            _buildKey('='),
          ],
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  // ============================================================
  // KEY
  // ============================================================

  Widget _buildKey(String value) {
    final bool isEquals = value == '=';

    final bool isOperator = ['÷', '×', '−', '+', 'xʸ', '%'].contains(value);

    final bool isFunction = [
      'sin',
      'cos',
      'tan',
      'sin⁻¹',
      'cos⁻¹',
      'tan⁻¹',
      '√',
      'x²',
      'ln',
      'log',
      '1/x',
      'π',
      'e',
      '(',
      ')',
    ].contains(value);

    final bool isDanger = value == 'AC' || value == '⌫';

    Color backgroundColor = button;
    Color foregroundColor = Colors.white;

    if (isEquals) {
      backgroundColor = cyan;
      foregroundColor = const Color(0xFF151518);
    } else if (isDanger) {
      backgroundColor = danger.withValues(alpha: 0.12);
      foregroundColor = danger;
    } else if (isOperator) {
      backgroundColor = cyan.withValues(alpha: 0.10);
      foregroundColor = cyan;
    } else if (isFunction) {
      backgroundColor = buttonLight;
      foregroundColor = cyan;
    }

    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: () => _press(value),

        borderRadius: BorderRadius.circular(15),

        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,

            borderRadius: BorderRadius.circular(15),

            border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
          ),

          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),

              child: FittedBox(
                fit: BoxFit.scaleDown,

                child: Text(
                  value,

                  style: TextStyle(
                    color: foregroundColor,

                    fontSize: isFunction ? 12 : 18,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCIENTIFIC EVALUATOR
// ============================================================

class _ScientificEvaluator {
  final bool degrees;

  _ScientificEvaluator({required this.degrees});

  double evaluate(Expression expression) {
    final evaluator = RealEvaluator(ContextModel());

    final num result = evaluator.evaluate(expression);

    // IMPORTANT:
    // RealEvaluator restituisce num.
    // Convertiamo esplicitamente in double.
    return result.toDouble();
  }
}
