import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // Si no está presente el archivo .env, continuará sin interrumpir la app
  }
  runApp(const CalculadoraOfertasApp());
}

class CalculadoraOfertasApp extends StatelessWidget {
  const CalculadoraOfertasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculadora For Status Whatsapp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAF9F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25D366),
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: const AppSplashScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// PANTALLA DE INICIO (SPLASH SCREEN CON EL ICONO PERSONALIZADO)
// -----------------------------------------------------------------------------
class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const OfferCalculatorScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF42B6FF),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Image.asset(
              'assets/app_icon.png',
              width: 240,
              height: 240,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class OfferCalculatorScreen extends StatefulWidget {
  const OfferCalculatorScreen({super.key});

  @override
  State<OfferCalculatorScreen> createState() => _OfferCalculatorScreenState();
}

class _OfferCalculatorScreenState extends State<OfferCalculatorScreen> {
  String get _geminiApiKey {
    final fromDotenv = dotenv.env['GEMINI_API_KEY'];
    if (fromDotenv != null && fromDotenv.trim().isNotEmpty) {
      return fromDotenv.trim();
    }
    const fromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return '';
  }

  static const String _extractionPrompt = '''
Eres un asistente experto en extracción de datos en lenguaje natural para una tienda de calzado y ropa en México.
Lee el texto dictado por el usuario y devuelve ÚNICAMENTE un JSON válido con esta estructura exacta:
{
  "costo": 500,
  "categoria": "caballero",
  "extra": 0,
  "tipo": "calzado",
  "nombre_producto": "Tenis Pirma",
  "tallas": ["22", "23", "24", "25"]
}
Reglas:
- "costo": número del precio de costo (ej. si dice "cuestan 500" o "me costó 400", pon 500 o 400).
- "categoria": únicamente 'dama', 'caballero' o 'niño'.
- "extra": ganancia adicional mencionada (10, 15, 20 o 30). Si no menciona ganancia extra, pon 0.
- "tipo": 'calzado' (si habla de tenis, zapatos, botas, sandalias, huaraches, corrida numérica) o 'prenda' (si habla de ropa, suéter, blusa, pantalón, camisa, playera, vestido).
- "nombre_producto": si menciona marca o artículo específico (ej. "Tenis Pirma", "Suéter", "Blusa"), ponlo con inicial mayúscula; si no, pon "".
- "tallas": lista de strings.
  * Para calzado: tallas individuales enteras ["22", "23", "24", "25"].
  * Para prendas: usa ÚNICAMENTE las siglas ["CH", "M", "G", "XG", "Unitalla"] si dice chica, mediana, grande, extra grande o unitalla. Si dice "de chica a grande", pon ["CH", "M", "G"].
''';

  double _costPrice = 25.00;
  int? _selectedExtra; // Opcional (10, 15, 20 o 30)
  String? _selectedProductType; // 'Calzado' o 'Prenda'
  String? _customProductName; // Ej. "Tenis Pirma"
  String? _selectedCategory; // 'Dama', 'Caballero', 'Niño'
  final List<String> _selectedSizes = []; // Tallas marcadas
  XFile? _selectedImage;

  // Variables para dictado por voz e IA
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isProcessingAI = false;
  String _spokenText = '';
  bool _alreadyProcessedCurrentSpeech = false;

  // Paso activo:
  // 1 = Costo, 2 = Ganancia extra, 3 = Producto, 4 = Categoría, 5 = Tallas, 6 = Foto, 7 = Completado
  int _activeStep = 1;
  bool _costCompleted = false;
  bool _extraCompleted = false;
  bool _productTypeCompleted = false;
  bool _categoryCompleted = false;
  bool _sizeCompleted = false;
  bool _photoCompleted = false;
  bool _rangeFilled = false;

  late final TextEditingController _costController;
  late final FocusNode _costFocusNode;
  late final ScrollController _scrollController;
  final ImagePicker _picker = ImagePicker();

  final List<int> _extraOptions = [10, 15, 20, 30];

  final List<String> _damaFootwearSizes = [
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
  ];

  final List<String> _caballeroFootwearSizes = [
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
  ];

  final List<String> _ninoFootwearSizes = [
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
  ];

  final List<String> _adultClothingSizes = [
    'CH',
    'M',
    'G',
    'XG',
    'Unitalla',
  ];

  final List<String> _ninoClothingSizes = [
    '2',
    '4',
    '6',
    '8',
    '10',
    '12',
    '14',
    '16',
    'CH',
    'M',
    'G',
    'Unitalla',
  ];

  @override
  void initState() {
    super.initState();
    _costController = TextEditingController(
      text: _costPrice.toStringAsFixed(2),
    );
    _costFocusNode = FocusNode();
    _scrollController = ScrollController();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              setState(() {
                _isListening = false;
              });
              if (_spokenText.trim().isNotEmpty &&
                  !_alreadyProcessedCurrentSpeech) {
                _alreadyProcessedCurrentSpeech = true;
                _processTextWithGemini(_spokenText);
              }
            }
          }
        },
        onError: (errorNotification) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
          });
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _costController.dispose();
    _costFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LÓGICA DE DICTADO POR VOZ + RESPUESTA EN TIEMPO REAL + GEMINI
  // ---------------------------------------------------------------------------
  Future<void> _toggleVoiceDictation() async {
    FocusScope.of(context).unfocus();

    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
      if (_spokenText.trim().isNotEmpty && !_alreadyProcessedCurrentSpeech) {
        _alreadyProcessedCurrentSpeech = true;
        await _processTextWithGemini(_spokenText);
      }
      return;
    }

    if (!_speechAvailable) {
      await _initSpeech();
    }

    if (!_speechAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El micrófono no está disponible o falta permiso de audio.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _spokenText = '';
      _isListening = true;
      _alreadyProcessedCurrentSpeech = false;
    });

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'es_MX',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: false,
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _spokenText = result.recognizedWords;
        });

        // ACTUALIZACIÓN EN TIEMPO REAL MIENTRAS EL USUARIO DICTA
        _applyRealtimeExtraction(result.recognizedWords);

        if (result.finalResult &&
            _spokenText.trim().isNotEmpty &&
            !_alreadyProcessedCurrentSpeech) {
          _alreadyProcessedCurrentSpeech = true;
          setState(() {
            _isListening = false;
          });
          _processTextWithGemini(_spokenText);
        }
      },
    );
  }

  void _applyRealtimeExtraction(String currentSpeech) {
    if (currentSpeech.trim().isEmpty) return;
    final Map<String, dynamic> localData =
        _extractNaturalLanguageLocal(currentSpeech);

    final dynamic rawCost = localData['costo'];
    final double? parsedCost = rawCost is num
        ? rawCost.toDouble()
        : double.tryParse(rawCost?.toString() ?? '');

    final String category = localData['categoria']?.toString() ?? '';
    final String type = localData['tipo']?.toString() ?? '';
    final String name = localData['nombre_producto']?.toString() ?? '';
    final List<String> sizes =
        (localData['tallas'] as List?)?.map((e) => e.toString()).toList() ??
            [];
    final int extra = (localData['extra'] as num?)?.round() ?? 0;

    setState(() {
      if (parsedCost != null && parsedCost > 0) {
        _costPrice = parsedCost;
        _costController.text = _costPrice.toStringAsFixed(2);
        _costCompleted = true;
      }

      if (_extraOptions.contains(extra)) {
        _selectedExtra = extra;
        _extraCompleted = true;
      }

      if (type == 'prenda') {
        _selectedProductType = 'Prenda';
        _productTypeCompleted = true;
      } else if (type == 'calzado') {
        _selectedProductType = 'Calzado';
        _productTypeCompleted = true;
      }

      if (name.isNotEmpty) {
        _customProductName = name;
      }

      if (category == 'caballero') {
        _selectedCategory = 'Caballero';
        _categoryCompleted = true;
      } else if (category == 'niño') {
        _selectedCategory = 'Niño';
        _categoryCompleted = true;
      } else if (category == 'dama') {
        _selectedCategory = 'Dama';
        _categoryCompleted = true;
      }

      if (sizes.isNotEmpty) {
        _selectedSizes
          ..clear()
          ..addAll(sizes);
        _rangeFilled = sizes.length > 1;
        _sizeCompleted = true;
      }
    });
  }

  Future<void> _processTextWithGemini(String spokenText) async {
    if (spokenText.trim().isEmpty) return;

    setState(() {
      _isProcessingAI = true;
    });

    final Map<String, dynamic> localParsed =
        _extractNaturalLanguageLocal(spokenText);
    Map<String, dynamic>? geminiData;

    if (_geminiApiKey.isEmpty) {
      if (!mounted) return;
      _applyExtractedData(localParsed);
      return;
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _geminiApiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
        ),
      );

      final prompt = '$_extractionPrompt\n\nTexto: "$spokenText"';
      final response = await model.generateContent([Content.text(prompt)]);
      final rawText = response.text ?? '';

      if (rawText.isNotEmpty) {
        final cleanedJson = rawText
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final decoded = jsonDecode(cleanedJson);
        if (decoded is Map<String, dynamic>) {
          geminiData = decoded;
        }
      }
    } catch (_) {
      geminiData = null;
    }

    final Map<String, dynamic> finalData = {
      'costo': geminiData?['costo'] ?? localParsed['costo'],
      'categoria': geminiData?['categoria'] ?? localParsed['categoria'],
      'extra': geminiData?['extra'] ?? localParsed['extra'],
      'tipo': geminiData?['tipo'] ?? localParsed['tipo'],
      'nombre_producto':
          (geminiData?['nombre_producto']?.toString().trim().isNotEmpty ??
                  false)
              ? geminiData!['nombre_producto']
              : localParsed['nombre_producto'],
      'tallas': (geminiData?['tallas'] is List &&
              (geminiData!['tallas'] as List).isNotEmpty)
          ? geminiData['tallas']
          : localParsed['tallas'],
    };

    if (!mounted) return;
    _applyExtractedData(finalData);
  }

  Map<String, dynamic> _extractNaturalLanguageLocal(String text) {
    final lower = text.toLowerCase();

    // 1. Categoría
    String categoria = 'dama';
    if (lower.contains('caballero') ||
        lower.contains('hombre') ||
        lower.contains('varón') ||
        lower.contains('varon')) {
      categoria = 'caballero';
    } else if (lower.contains('niño') ||
        lower.contains('nino') ||
        lower.contains('niña') ||
        lower.contains('nina') ||
        lower.contains('infantil')) {
      categoria = 'niño';
    } else if (lower.contains('dama') ||
        lower.contains('mujer') ||
        lower.contains('señora') ||
        lower.contains('senora')) {
      categoria = 'dama';
    }

    // 2. Tipo de producto y nombre específico
    String tipo = 'calzado';
    if (lower.contains('prenda') ||
        lower.contains('ropa') ||
        lower.contains('suéter') ||
        lower.contains('sueter') ||
        lower.contains('blusa') ||
        lower.contains('camisa') ||
        lower.contains('pantalón') ||
        lower.contains('pantalon') ||
        lower.contains('vestido') ||
        lower.contains('playera') ||
        lower.contains('chamarra') ||
        lower.contains('sudadera') ||
        lower.contains('falda')) {
      tipo = 'prenda';
    }

    String nombreProducto = '';
    final brandMatch = RegExp(
      r'\b(tenis|tennis|zapatos?|botas?|sandalias?|huaraches?|tacones?|suéter|sueter|blusa|pantalón|pantalon|camisa|playera|chamarra|sudadera|vestido)(?:\s+([a-záéíóúñ]+))?',
      caseSensitive: false,
    ).firstMatch(text);

    if (brandMatch != null) {
      final String itemWord = brandMatch.group(1)!;
      final String? secondWord = brandMatch.group(2);
      final Set<String> stopWords = {
        'de',
        'para',
        'dama',
        'caballero',
        'hombre',
        'mujer',
        'niño',
        'nino',
        'niña',
        'nina',
        'cuesta',
        'cuestan',
        'costo',
        'costó',
        'en',
        'con',
        'que',
        'me',
        'vale',
        'valen',
        'hay',
        'talla',
        'tallas',
        'corrida',
        'del',
      };
      String normalizedItem = itemWord.toLowerCase() == 'tennis'
          ? 'Tenis'
          : _capitalize(itemWord);
      if (secondWord != null &&
          !stopWords.contains(secondWord.toLowerCase())) {
        nombreProducto = '$normalizedItem ${_capitalize(secondWord)}';
      } else {
        nombreProducto = normalizedItem;
      }
    }

    // 3. Tallas de calzado o prenda
    final List<String> tallas = [];
    final Set<int> sizeNumbersUsedInText = {};

    // Calzado numérico (ej. "corrida del 22 al 25", "del 22 al 26")
    final rangeMatch = RegExp(
      r'(?:corrida\s+)?(?:del?|de\s+la|tallas?\s+de\s+la|tallas?\s+del?|tallas?)\s*(\d{1,2})(?:\.\d+)?\s*(?:al?|hasta\s+el|hasta\s+la)\s*(\d{1,2})(?:\.\d+)?',
    ).firstMatch(lower);

    if (rangeMatch != null) {
      final int start = int.parse(rangeMatch.group(1)!);
      final int end = int.parse(rangeMatch.group(2)!);
      sizeNumbersUsedInText.add(start);
      sizeNumbersUsedInText.add(end);
      final int minSize = start < end ? start : end;
      final int maxSize = start > end ? start : end;
      if (minSize >= 2 && maxSize <= 32) {
        final int step = (tipo == 'prenda' && maxSize <= 16) ? 2 : 1;
        for (int s = minSize; s <= maxSize; s += step) {
          tallas.add(s.toString());
        }
      }
    }

    // Exclusión "menos el 23"
    final excludeMatch = RegExp(
      r'(?:menos|sin|excepto)\s+(?:el\s+|la\s+)?(\d{1,2})',
    ).allMatches(lower);
    for (final m in excludeMatch) {
      final String excluded = m.group(1)!;
      sizeNumbersUsedInText.add(int.parse(excluded));
      tallas.remove(excluded);
    }

    // Tallas de prenda (CH, M, G, XG, Unitalla)
    if (lower.contains('unitalla')) {
      tallas
        ..clear()
        ..add('Unitalla');
    } else if (tipo == 'prenda' || tallas.isEmpty) {
      if (RegExp(r'(?:de\s+)?chica\s+(?:a|al?|hasta)\s+grande').hasMatch(lower)) {
        tallas.addAll(['CH', 'M', 'G']);
      } else if (RegExp(r'(?:de\s+)?chica\s+(?:a|al?|hasta)\s+extra\s*grande').hasMatch(lower)) {
        tallas.addAll(['CH', 'M', 'G', 'XG']);
      } else if (RegExp(r'(?:de\s+)?mediana\s+(?:a|al?|hasta)\s+grande').hasMatch(lower)) {
        tallas.addAll(['M', 'G']);
      } else {
        if (RegExp(r'\b(chica|chicas|ch)\b').hasMatch(lower)) {
          if (!tallas.contains('CH')) tallas.add('CH');
        }
        if (RegExp(r'\b(mediana|medianas|m)\b').hasMatch(lower)) {
          if (!tallas.contains('M')) tallas.add('M');
        }
        if (RegExp(r'\b(grande|grandes|g)\b').hasMatch(lower)) {
          if (!tallas.contains('G')) tallas.add('G');
        }
        if (RegExp(r'\b(extra\s*grande|extra\s*grandes|xg|xl)\b').hasMatch(lower)) {
          if (!tallas.contains('XG')) tallas.add('XG');
        }
      }
    }

    // 4. Ganancia extra
    int extra = 0;
    final extraMatch = RegExp(
      r'(?:ganar(?:le)?|ganancia|extra|sumar(?:le)?|más|mas)\s*(?:de\s*)?\$?\s*(10|15|20|30)\b',
    ).firstMatch(lower);
    if (extraMatch != null) {
      extra = int.parse(extraMatch.group(1)!);
      sizeNumbersUsedInText.add(extra);
    }

    // 5. Costo
    double costo = _costPrice;
    final costoExplicitMatch = RegExp(
      r'(?:costó|costo|cuestan|cuesta|valen|vale|compré\s+en|compre\s+en|precio|a)\s*(?:de\s*)?\$?\s*(\d+(?:[.,]\d+)?)',
    ).firstMatch(lower);

    if (costoExplicitMatch != null) {
      costo = double.tryParse(
            costoExplicitMatch.group(1)!.replaceAll(',', '.'),
          ) ??
          costo;
    } else {
      final allNums = RegExp(r'\d+(?:[.,]\d+)?')
          .allMatches(lower)
          .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0.0)
          .where((n) => !sizeNumbersUsedInText.contains(n.round()))
          .toList();
      if (allNums.isNotEmpty) {
        costo = allNums.first;
      }
    }

    return {
      'costo': costo,
      'categoria': categoria,
      'extra': extra,
      'tipo': tipo,
      'nombre_producto': nombreProducto,
      'tallas': tallas,
    };
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  void _applyExtractedData(Map<String, dynamic> data) {
    final dynamic rawCost = data['costo'];
    final double parsedCost = rawCost is num
        ? rawCost.toDouble()
        : (double.tryParse(rawCost?.toString() ?? '') ?? _costPrice);

    final String rawCategory =
        (data['categoria']?.toString() ?? '').toLowerCase().trim();
    String mappedCategory = 'Dama';
    if (rawCategory.contains('caballero')) {
      mappedCategory = 'Caballero';
    } else if (rawCategory.contains('niñ') || rawCategory.contains('nin')) {
      mappedCategory = 'Niño';
    } else if (rawCategory.contains('dama')) {
      mappedCategory = 'Dama';
    }

    final dynamic rawExtra = data['extra'];
    final int parsedExtra = rawExtra is num
        ? rawExtra.round()
        : (int.tryParse(rawExtra?.toString() ?? '0') ?? 0);

    final String rawTipo =
        (data['tipo']?.toString() ?? 'calzado').toLowerCase().trim();
    final String productType =
        rawTipo.contains('prenda') ? 'Prenda' : 'Calzado';

    final String customName =
        (data['nombre_producto']?.toString() ?? '').trim();

    final List<String> extractedSizes = [];
    if (data['tallas'] is List) {
      for (final item in (data['tallas'] as List)) {
        final String s = item.toString().trim();
        if (s.isNotEmpty && !extractedSizes.contains(s)) {
          extractedSizes.add(s);
        }
      }
    }

    setState(() {
      _isProcessingAI = false;

      // 1. Costo
      _costPrice = parsedCost;
      _costController.text = _costPrice.toStringAsFixed(2);
      _costCompleted = true;

      // 2. Ganancia extra
      if (_extraOptions.contains(parsedExtra)) {
        _selectedExtra = parsedExtra;
      } else {
        _selectedExtra = null;
      }
      _extraCompleted = true;

      // 3. Producto
      _selectedProductType = productType;
      _customProductName = customName.isNotEmpty ? customName : null;
      _productTypeCompleted = true;

      // 4. Categoría
      _selectedCategory = mappedCategory;
      _categoryCompleted = true;

      // 5. Tallas
      _selectedSizes.clear();
      if (extractedSizes.isNotEmpty) {
        _selectedSizes.addAll(extractedSizes);
        _rangeFilled = extractedSizes.length > 1;
        _sizeCompleted = true;
        _activeStep = 6;
      } else {
        _rangeFilled = false;
        _sizeCompleted = false;
        _activeStep = 5;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1B873F),
        content: Text(
          'Listo: $_generatedOfferMessage',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Fórmula: Costo + (Costo * 0.50) + GananciaExtra
  double get _baseProfit => _costPrice * 0.50;
  double get _totalProfit => _baseProfit + (_selectedExtra ?? 0);
  double get _finalPrice => _costPrice + _totalProfit;

  List<String> get _currentSizeOptions {
    final String product = _selectedProductType ?? 'Calzado';
    final String category = _selectedCategory ?? 'Dama';

    List<String> baseList;
    if (product == 'Prenda') {
      if (category == 'Niño') {
        baseList = List<String>.from(_ninoClothingSizes);
      } else {
        baseList = List<String>.from(_adultClothingSizes);
      }
    } else {
      if (category == 'Caballero') {
        baseList = List<String>.from(_caballeroFootwearSizes);
      } else if (category == 'Niño') {
        baseList = List<String>.from(_ninoFootwearSizes);
      } else {
        baseList = List<String>.from(_damaFootwearSizes);
      }
    }

    for (final s in _selectedSizes) {
      if (!baseList.contains(s)) {
        baseList.add(s);
      }
    }
    return baseList;
  }

  // Si son consecutivas muestra rango "CH a G" o "22 a 25", sino las lista separadas
  String get _sizesFormatted {
    if (_selectedSizes.isEmpty) return '';
    final List<String> options = _currentSizeOptions;
    final List<int> indices = [];
    for (int i = 0; i < options.length; i++) {
      if (_selectedSizes.contains(options[i])) {
        indices.add(i);
      }
    }
    if (indices.isEmpty) return _selectedSizes.join(', ');
    if (indices.length == 1) return options[indices.first];

    bool isContinuous = true;
    for (int i = 1; i < indices.length; i++) {
      if (indices[i] != indices[i - 1] + 1) {
        isContinuous = false;
        break;
      }
    }

    if (isContinuous) {
      return '${options[indices.first]} a ${options[indices.last]}';
    }
    return indices.map((i) => options[i]).join(', ');
  }

  String get _generatedOfferMessage {
    final String productLabel =
        (_customProductName != null && _customProductName!.isNotEmpty)
            ? _customProductName!
            : (_selectedProductType ?? 'Calzado');
    final String category = _selectedCategory ?? 'Dama';
    final String price = _finalPrice.toStringAsFixed(2);
    if (_selectedSizes.isNotEmpty) {
      return '$productLabel de $category precio de oferta \$$price tallas $_sizesFormatted';
    }
    return '$productLabel de $category precio de oferta \$$price';
  }

  void _clearAndFocusCost() {
    setState(() {
      _costController.clear();
      _costPrice = 0.0;
    });
    _costFocusNode.requestFocus();
  }

  void _resetAll() {
    _speech.stop();
    setState(() {
      _isListening = false;
      _isProcessingAI = false;
      _spokenText = '';
      _costController.clear();
      _costPrice = 0.0;
      _selectedExtra = null;
      _selectedProductType = null;
      _customProductName = null;
      _selectedCategory = null;
      _selectedSizes.clear();
      _rangeFilled = false;
      _selectedImage = null;
      _costCompleted = false;
      _extraCompleted = false;
      _productTypeCompleted = false;
      _categoryCompleted = false;
      _sizeCompleted = false;
      _photoCompleted = false;
      _activeStep = 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      _costFocusNode.requestFocus();
    });
  }

  void _onCostChanged(String value) {
    final normalized = value.replaceAll(',', '.');
    final parsed = double.tryParse(normalized) ?? 0.0;
    setState(() {
      _costPrice = parsed;
    });
  }

  void _completeCostStep() {
    FocusScope.of(context).unfocus();
    _costController.text = _costPrice.toStringAsFixed(2);
    setState(() {
      _costCompleted = true;
      _activeStep = 2;
    });
  }

  void _toggleExtraOption(int amount) {
    setState(() {
      if (_selectedExtra == amount) {
        _selectedExtra = null;
      } else {
        _selectedExtra = amount;
        _extraCompleted = true;
        _activeStep = 3;
      }
    });
  }

  void _completeExtraStep() {
    setState(() {
      _extraCompleted = true;
      _activeStep = 3;
    });
  }

  void _selectProductType(String type) {
    setState(() {
      if (_selectedProductType != type) {
        _selectedSizes.clear();
        _rangeFilled = false;
        _sizeCompleted = false;
        _customProductName = null;
      }
      _selectedProductType = type;
      _productTypeCompleted = true;
      _activeStep = 4;
    });
  }

  void _selectCategory(String category) {
    setState(() {
      if (_selectedCategory != category) {
        _selectedSizes.clear();
        _rangeFilled = false;
        _sizeCompleted = false;
      }
      _selectedCategory = category;
      _categoryCompleted = true;
      _activeStep = 5;
    });
  }

  void _onSizeTap(String tappedSize) {
    final List<String> options = _currentSizeOptions;
    final int tappedIndex = options.indexOf(tappedSize);
    if (tappedIndex == -1) return;

    setState(() {
      if (tappedSize == 'Unitalla') {
        if (_selectedSizes.contains('Unitalla')) {
          _selectedSizes.clear();
        } else {
          _selectedSizes
            ..clear()
            ..add('Unitalla');
        }
        _rangeFilled = false;
        return;
      }

      _selectedSizes.remove('Unitalla');

      if (_selectedSizes.contains(tappedSize)) {
        _selectedSizes.remove(tappedSize);
        if (_selectedSizes.isEmpty) {
          _rangeFilled = false;
        }
        return;
      }

      if (_selectedSizes.isEmpty) {
        _selectedSizes.add(tappedSize);
        _rangeFilled = false;
        return;
      }

      if (_selectedSizes.length == 1 && !_rangeFilled) {
        final String firstSize = _selectedSizes.first;
        final int firstIndex = options.indexOf(firstSize);
        final int start = firstIndex < tappedIndex ? firstIndex : tappedIndex;
        final int end = firstIndex > tappedIndex ? firstIndex : tappedIndex;
        _selectedSizes.clear();
        for (int i = start; i <= end; i++) {
          if (options[i] != 'Unitalla') {
            _selectedSizes.add(options[i]);
          }
        }
        _rangeFilled = true;
        return;
      }

      _selectedSizes.add(tappedSize);
    });
  }

  void _completeSizeStep() {
    setState(() {
      _sizeCompleted = true;
      _activeStep = 6;
    });
  }

  Future<void> _pickPhotoFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (photo != null) {
        setState(() {
          _selectedImage = photo;
          _photoCompleted = true;
          _activeStep = 7;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir la galería: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _shareOnWhatsAppStatus() async {
    final String shareText = _generatedOfferMessage;

    if (_selectedImage != null) {
      await Share.shareXFiles(
        [_selectedImage!],
        text: shareText,
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elige una foto de la galería para compartir.'),
          duration: Duration(seconds: 2),
        ),
      );
      setState(() {
        _activeStep = 6;
      });
      await _pickPhotoFromGallery();
      if (_selectedImage != null) {
        await Share.shareXFiles(
          [_selectedImage!],
          text: shareText,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        toolbarHeight: 48,
        automaticallyImplyLeading: false,
        title: const Text(
          'Calculadora For Status Whatsapp',
          style: TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildVoiceDictationButton(),
              const SizedBox(height: 10),
              _buildCostCard(),
              const SizedBox(height: 8),
              _buildExtraProfitCard(),
              const SizedBox(height: 8),
              _buildProductTypeCard(),
              const SizedBox(height: 8),
              _buildCategoryCard(),
              const SizedBox(height: 8),
              _buildSizesCard(),
              const SizedBox(height: 8),
              _buildPhotoCard(),
              const SizedBox(height: 10),
              _buildFinalPriceCard(),
              const SizedBox(height: 12),
              _buildShareButton(),
              const SizedBox(height: 8),
              _buildClearButton(),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTÓN DESTACADO DE DICTADO POR VOZ CON IA ("Tocar para dictar")
  // ---------------------------------------------------------------------------
  Widget _buildVoiceDictationButton() {
    final Color bgColor = _isListening
        ? const Color(0xFFDC2626)
        : _isProcessingAI
            ? const Color(0xFF2563EB)
            : const Color(0xFF18181B);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isProcessingAI ? null : _toggleVoiceDictation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isProcessingAI)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? Colors.white.withValues(alpha: 0.25)
                              : const Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isListening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isListening
                                ? 'Escuchando y llenando campos...'
                                : _isProcessingAI
                                    ? 'Afinando con IA...'
                                    : 'Tocar para dictar',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isListening
                                ? 'Ej: "Blusa de dama cuesta 200 tallas chica, mediana y grande"'
                                : 'Dicta en voz normal: llena los campos en vivo mientras hablas',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_spokenText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '"$_spokenText"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. COSTO DEL PRODUCTO
  // ---------------------------------------------------------------------------
  Widget _buildCostCard() {
    final bool isExpanded = _activeStep == 1;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 1),
            child: Row(
              children: [
                if (_costCompleted && !isExpanded) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1DB954),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: Text(
                    '1. Costo del producto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _costCompleted && !isExpanded
                        ? const Color(0xFFE0F5E9)
                        : const Color(0xFFEFECE6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '\$${_costPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _costCompleted && !isExpanded
                          ? const Color(0xFF0A2E16)
                          : const Color(0xFF4A4A4A),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _clearAndFocusCost,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F2ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '\$',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IntrinsicWidth(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 100),
                        child: TextField(
                          controller: _costController,
                          focusNode: _costFocusNode,
                          onTap: () {
                            _costController.clear();
                            setState(() {
                              _costPrice = 0.0;
                            });
                          },
                          onChanged: _onCostChanged,
                          onSubmitted: (_) => _completeCostStep(),
                          textInputAction: TextInputAction.done,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*[.,]?\d{0,2}'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF18181B),
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: '0.00',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: _completeCostStep,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF18181B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Siguiente',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. GANANCIA EXTRA (Opcional)
  // ---------------------------------------------------------------------------
  Widget _buildExtraProfitCard() {
    final bool isExpanded = _activeStep == 2;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 2),
            child: Row(
              children: [
                if (_extraCompleted && !isExpanded) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1DB954),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: Text(
                    '2. Ganancia extra',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedExtra != null
                        ? const Color(0xFFFCE2C4)
                        : const Color(0xFFEFECE6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _selectedExtra != null
                        ? '+\$$_selectedExtra'
                        : 'Opcional',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _selectedExtra != null
                          ? const Color(0xFF5C3A1D)
                          : const Color(0xFF52525B),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _extraOptions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.6,
              ),
              itemBuilder: (context, index) {
                final int amount = _extraOptions[index];
                final bool isSelected = _selectedExtra == amount;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleExtraOption(amount),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          isSelected ? Colors.white : const Color(0xFFF4F2ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7CA6F8)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      '+\$$amount',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? const Color(0xFF18181B)
                            : const Color(0xFF3F3F46),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: _completeExtraStep,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD4D4D8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _selectedExtra == null ? 'Omitir paso' : 'Siguiente',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF27272A),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. TIPO DE PRODUCTO (Calzado / Prenda)
  // ---------------------------------------------------------------------------
  Widget _buildProductTypeCard() {
    final bool isExpanded = _activeStep == 3;
    final List<String> productTypes = ['Calzado', 'Prenda'];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 3),
            child: Row(
              children: [
                if (_productTypeCompleted && !isExpanded) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1DB954),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: Text(
                    '3. Tipo de producto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                if (_selectedProductType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _customProductName ?? _selectedProductType!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0A2E16),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            Row(
              children: productTypes.map((label) {
                final bool isSelected = _selectedProductType == label;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectProductType(label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFFF4F2ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF7CA6F8)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF18181B),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. CATEGORÍA (Dama / Caballero / Niño)
  // ---------------------------------------------------------------------------
  Widget _buildCategoryCard() {
    final bool isExpanded = _activeStep == 4;
    final List<String> categories = ['Dama', 'Caballero', 'Niño'];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 4),
            child: Row(
              children: [
                if (_categoryCompleted && !isExpanded) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1DB954),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: Text(
                    '4. Categoría',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                if (_selectedCategory != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _selectedCategory!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0A2E16),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            Row(
              children: categories.map((label) {
                final bool isSelected = _selectedCategory == label;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectCategory(label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFFF4F2ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF7CA6F8)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF18181B),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. TALLAS (Solo enteros, marca camino y permite desmarcar)
  // ---------------------------------------------------------------------------
  Widget _buildSizesCard() {
    final bool isExpanded = _activeStep == 5;
    final List<String> options = _currentSizeOptions;
    final bool hasSizes = _selectedSizes.isNotEmpty;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 5),
            child: Row(
              children: [
                if (_sizeCompleted && !isExpanded) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1DB954),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: Text(
                    '5. Tallas',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: hasSizes
                          ? const Color(0xFFE0F5E9)
                          : const Color(0xFFEFECE6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      hasSizes ? _sizesFormatted : 'Opcional',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: hasSizes
                            ? const Color(0xFF0A2E16)
                            : const Color(0xFF52525B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((size) {
                final bool isSelected = _selectedSizes.contains(size);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _onSizeTap(size),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? Colors.white : const Color(0xFFF4F2ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7CA6F8)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      size,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF18181B),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (hasSizes) ...[
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _selectedSizes.clear();
                        _rangeFilled = false;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 38),
                      side: const BorderSide(color: Color(0xFFD4D4D8)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Borrar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF52525B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: hasSizes
                        ? FilledButton(
                            onPressed: _completeSizeStep,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF18181B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Siguiente ($_sizesFormatted)',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : OutlinedButton(
                            onPressed: _completeSizeStep,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFD4D4D8)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Omitir talla',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF27272A),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. FOTO DEL PRODUCTO (Solo Galería)
  // ---------------------------------------------------------------------------
  Widget _buildPhotoCard() {
    final bool isExpanded = _activeStep == 6;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 6),
            child: Row(
              children: [
                if (_photoCompleted && !isExpanded) ...[
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1DB954),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: Text(
                    '6. Foto del producto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                if (_selectedImage != null && !isExpanded)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(_selectedImage!.path),
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 10),
            if (_selectedImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_selectedImage!.path),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _pickPhotoFromGallery,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F2ED),
                  foregroundColor: const Color(0xFF18181B),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text(
                  'Elegir de galería',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRECIO FINAL Y VISTA PREVIA DEL MENSAJE
  // ---------------------------------------------------------------------------
  Widget _buildFinalPriceCard() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Precio Final',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF63FF83),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Sugerido',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0A2E16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F2ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '\$ ${_finalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Costo \$${_costPrice.toStringAsFixed(2)} + Ganancia \$${_totalProfit.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF52525B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _generatedOfferMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTÓN DE ACCIÓN ("Compartir en Estado")
  // ---------------------------------------------------------------------------
  Widget _buildShareButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _shareOnWhatsAppStatus,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          elevation: 2,
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.chat_outlined, size: 20),
        label: const Text(
          'Compartir en Estado',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTÓN LIMPIAR
  // ---------------------------------------------------------------------------
  Widget _buildClearButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _resetAll,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF3F3F46),
          side: const BorderSide(color: Color(0xFFD4D4D8), width: 1.5),
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.refresh_rounded, size: 19),
        label: const Text(
          'Limpiar',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
