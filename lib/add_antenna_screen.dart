import 'package:flutter/material.dart';

import 'services/api_service.dart';

class AddAntennaScreen extends StatefulWidget {
  const AddAntennaScreen({super.key});

  @override
  State<AddAntennaScreen> createState() => _AddAntennaScreenState();
}

class _AddAntennaScreenState extends State<AddAntennaScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controller per i campi di testo principali
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  // Controller per le specifiche tecniche
  final TextEditingController _freqController = TextEditingController(
    text: '94.5 MHz',
  );
  final TextEditingController _powerController = TextEditingController(
    text: '2 kW',
  );
  final TextEditingController _rosController = TextEditingController(
    text: '1.15',
  );
  final TextEditingController _tempController = TextEditingController(
    text: '38°C',
  );

  bool _isLoading = false;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _freqController.dispose();
    _powerController.dispose();
    _rosController.dispose();
    _tempController.dispose();
    super.dispose();
  }

  Future<void> _saveAntenna() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final antennaId = _idController.text.trim();

      await ApiService.instance.createAntenna({
        'code': antennaId,
        'name': _nameController.text.trim(),
        'lat': double.parse(_latController.text.trim()),
        'lng': double.parse(_lngController.text.trim()),
        'status': 'ATTIVA',
        'specs': {
          'frequencyMHz': _parseMeasurement(_freqController.text),
          'powerWatts':
              _parseMeasurement(_powerController.text) *
              (_powerController.text.toLowerCase().contains('kw') ? 1000 : 1),
          'ros': _parseMeasurement(_rosController.text),
          'temperature': _parseMeasurement(_tempController.text),
        },
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Antenna aggiunta con successo nel database!'),
        ),
      );

      Navigator.of(context).pop(); // Torna alla schermata precedente
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double _parseMeasurement(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll(',', '.');
    return double.parse(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Aggiungi Nuova Antenna'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dati Identificativi',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'ID Antenna (es. ANT-100)',
                ),
                validator: (val) => val == null || val.isEmpty
                    ? 'Inserisci un ID valido'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nome Antenna (es. Postazione Sud)',
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Inserisci un nome' : null,
              ),
              const SizedBox(height: 20),
              Text(
                'Coordinate GPS',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Latitudine',
                      ),
                      validator: (val) => double.tryParse(val ?? '') == null
                          ? 'Valore non valido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Longitudine',
                      ),
                      validator: (val) => double.tryParse(val ?? '') == null
                          ? 'Valore non valido'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Specifiche Tecniche',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _freqController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Frequenza'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _powerController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Potenza'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rosController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Valore ROS',
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _tempController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Temperatura',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveAntenna,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Color(0xFF10111A))
                    : const Text(
                        'CREA E SALVA NEL DATABASE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
