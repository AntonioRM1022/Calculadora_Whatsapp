import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      title: 'Calculadora AI',
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

class _OfferCalculatorScreenState extends State<OfferCalculatorScreen>
    with SingleTickerProviderStateMixin {
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
- "costo": número del precio de costo (ej. si dice "cuesta 800" o "me costó 500", pon 800 o 500). NUNCA confundas los números de las tallas (ej. "corrida del 20 al 25") con el costo.
- "categoria": 'dama', 'caballero', 'niño', 'niña', 'juniors', 'teens', 'bebe', 'beba' o 'unisex'.
- "extra": número de ganancia adicional si la menciona (ej. 10, 20, 25, 30, 40, 50, etc.). Si dice "no quiero ganar ganancias", "sin ganancia", o no menciona ganancia, pon 0.
- "tipo": 'calzado' (si habla de tenis, zapatos, botas, sandalias, huaraches, corrida numérica) o 'prenda' (si habla de ropa, suéter, blusa, pantalón, camisa, playera, vestido).
- "nombre_producto": si menciona marca o artículo específico (ej. "Tenis Pirma", "Suéter", "Blusa"), ponlo con inicial mayúscula; si no, pon "".
- "tallas": lista de strings de tallas.
  * Para calzado: tallas individuales enteras numéricas (ej. ["20", "21", "22", "23", "24", "25"]).
  * Para prendas: usa ÚNICAMENTE ["CH", "M", "G", "XG", "Unitalla"] si dice chica, mediana, grande, extra grande o unitalla. Si dice "de chica a grande", pon ["CH", "M", "G"].
''';

  double _costPrice = 25.00;
  int? _selectedExtra; // Opcional (10, 15, 20 o 30)
  String? _selectedProductType; // 'Tenis', 'Calzado' o 'Prenda'
  String? _selectedBrand; // Ej. "Nike", "Adidas", "Pirma"
  final TextEditingController _brandController = TextEditingController();
  String? _customProductName; // Ej. "Tenis Pirma"
  String? _selectedCategory; // 'Dama', 'Caballero', 'Niño'
  final List<String> _selectedSizes = []; // Tallas marcadas
  XFile? _selectedImage;

  // Variables para dictado por voz e IA
  late final stt.SpeechToText _speech;
  late final AnimationController _pulseController;
  bool _isAutoClosing = false;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isProcessingAI = false;
  String _spokenText = '';
  bool _alreadyProcessedCurrentSpeech = false;
  double _soundLevel = 0.0;
  double _spasmIntensity = 0.0;

  // Variables para escaneo de capturas con Gemini Vision (Price Shoes)
  bool _isScanningImage = false;
  String _scanStatusMessage = '';
  double? _previousPrice;
  double? _socioPrice;
  double? _promoCost;
  double? _customOfferPrice;
  bool _noProfitMode = false;

  double get _basePriceRoundedTo10 {
    if (_costPrice <= 0) return 0.0;
    final double with50 = _costPrice * 1.5;
    return (with50 / 10.0).ceil() * 10.0;
  }

  int get _roundingTo10Extra {
    if (_costPrice <= 0) return 0;
    final double with50 = _costPrice * 1.5;
    return math.max(0, (_basePriceRoundedTo10 - with50).round());
  }

  // Contador de uso de IA y tokens gratuitos diarios (1500 consultas/día)
  int _todayAiRequestsUsed = 0;
  int _todayTokensUsed = 0;
  static const int _dailyFreeRequestsLimit = 1500;

  int get _remainingAiRequests =>
      math.max(0, _dailyFreeRequestsLimit - _todayAiRequestsUsed);

  String get _shortProductTypeLabel {
    final String candidate =
        (_customProductName ?? _selectedProductType ?? 'Tenis').toLowerCase();
    String base;
    if (candidate.contains('tenis') ||
        candidate.contains('tennis') ||
        candidate.contains('sneaker') ||
        candidate.contains('running')) {
      base = 'Tenis';
    } else if (candidate.contains('zapato') || candidate.contains('mocas')) {
      base = 'Zapato';
    } else if (candidate.contains('bota') || candidate.contains('botin')) {
      base = 'Bota';
    } else if (candidate.contains('sandalia') || candidate.contains('chancla')) {
      base = 'Sandalia';
    } else if (candidate.contains('huarache')) {
      base = 'Huarache';
    } else if (candidate.contains('tacon') || candidate.contains('tacón')) {
      base = 'Tacón';
    } else if (candidate.contains('pantufla')) {
      base = 'Pantufla';
    } else if (candidate.contains('blusa')) {
      base = 'Blusa';
    } else if (candidate.contains('playera') || candidate.contains('remera')) {
      base = 'Playera';
    } else if (candidate.contains('pantalon') ||
        candidate.contains('pantalón') ||
        candidate.contains('jeans')) {
      base = 'Pantalón';
    } else if (candidate.contains('sueter') || candidate.contains('suéter')) {
      base = 'Suéter';
    } else if (candidate.contains('chamarra') || candidate.contains('chaqueta')) {
      base = 'Chamarra';
    } else if (candidate.contains('vestido')) {
      base = 'Vestido';
    } else if (candidate.contains('falda')) {
      base = 'Falda';
    } else if (candidate.contains('ropa') || candidate.contains('prenda')) {
      base = 'Prenda';
    } else {
      base = _selectedProductType ?? 'Tenis';
    }

    if (_selectedBrand != null && _selectedBrand!.trim().isNotEmpty) {
      final String brand = _selectedBrand!.trim();
      if (!base.toLowerCase().contains(brand.toLowerCase())) {
        return '$base $brand';
      }
    }
    return base;
  }

  Future<void> _loadDailyUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final savedDate = prefs.getString('ai_usage_date') ?? '';
      if (savedDate == todayStr) {
        if (mounted) {
          setState(() {
            _todayAiRequestsUsed = prefs.getInt('ai_usage_requests') ?? 0;
            _todayTokensUsed = prefs.getInt('ai_usage_tokens') ?? 0;
          });
        }
      } else {
        await prefs.setString('ai_usage_date', todayStr);
        await prefs.setInt('ai_usage_requests', 0);
        await prefs.setInt('ai_usage_tokens', 0);
        if (mounted) {
          setState(() {
            _todayAiRequestsUsed = 0;
            _todayTokensUsed = 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _recordAiUsage(int tokens) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final savedDate = prefs.getString('ai_usage_date') ?? '';
      int currentReq =
          (savedDate == todayStr) ? (prefs.getInt('ai_usage_requests') ?? 0) : 0;
      int currentTokens =
          (savedDate == todayStr) ? (prefs.getInt('ai_usage_tokens') ?? 0) : 0;
      currentReq += 1;
      currentTokens += tokens;
      await prefs.setString('ai_usage_date', todayStr);
      await prefs.setInt('ai_usage_requests', currentReq);
      await prefs.setInt('ai_usage_tokens', currentTokens);
      if (mounted) {
        setState(() {
          _todayAiRequestsUsed = currentReq;
          _todayTokensUsed = currentTokens;
        });
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // HISTORIAL DE OFERTAS
  // ---------------------------------------------------------------------------
  List<OfferHistoryItem> _historyItems = [];

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString('saved_offers_history');
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        if (mounted) {
          setState(() {
            _historyItems = decoded
                .map((e) =>
                    OfferHistoryItem.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHistoryToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded =
          jsonEncode(_historyItems.map((e) => e.toJson()).toList());
      await prefs.setString('saved_offers_history', encoded);
    } catch (_) {}
  }

  Future<void> _addOfferToHistory() async {
    final newItem = OfferHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      productType: _shortProductTypeLabel,
      category: _selectedCategory ?? 'Dama',
      cost: _costPrice,
      previousPrice: _previousPrice,
      finalPrice: _finalPrice,
      profit: _totalProfit,
      offerMessage: _generatedOfferMessage,
      imagePath: _selectedImage?.path,
      sizes: List<String>.from(_selectedSizes),
    );

    setState(() {
      _historyItems.insert(0, newItem);
      if (_historyItems.length > 50) {
        _historyItems = _historyItems.sublist(0, 50);
      }
    });
    await _saveHistoryToPrefs();
  }

  Future<void> _shareHistoryItem(OfferHistoryItem item) async {
    if (item.imagePath != null && File(item.imagePath!).existsSync()) {
      await Share.shareXFiles(
        [XFile(item.imagePath!)],
        text: item.offerMessage,
      );
    } else {
      await Share.share(item.offerMessage);
    }
  }

  // Bloqueo progresivo durante la sesión de dictado para evitar sobreescritura
  bool _sessionCostLocked = false;
  bool _sessionExtraLocked = false;
  bool _sessionTypeLocked = false;
  bool _sessionCategoryLocked = false;
  bool _sessionSizesLocked = false;

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
  late final TextEditingController _customExtraController;
  late final FocusNode _customExtraFocusNode;
  late final ScrollController _scrollController;
  final ImagePicker _picker = ImagePicker();

  final List<int> _extraOptions = [10, 20, 30, 40, 50];

  // Calzado según rangos de Price Shoes por categoría:
  final List<String> _damaFootwearSizes = ['20', '21', '22', '23', '24', '25'];
  final List<String> _caballeroFootwearSizes = [
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
    '31',
  ];
  final List<String> _ninoFootwearSizes = [
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
  ];
  final List<String> _ninaFootwearSizes = [
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
  ];
  final List<String> _juniorsFootwearSizes = [
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
  ];
  final List<String> _teensFootwearSizes = [
    '21',
    '22',
    '23',
    '24',
    '25',
  ];
  final List<String> _bebeFootwearSizes = [
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
  ];
  final List<String> _bebaFootwearSizes = [
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
  ];
  final List<String> _unisexFootwearSizes = [
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
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

  final List<String> _bebeClothingSizes = [
    '0-3M',
    '3-6M',
    '6-9M',
    '9-12M',
    '12-18M',
    '18-24M',
    '1',
    '2',
    '3',
  ];

  @override
  void initState() {
    super.initState();
    _costController = TextEditingController(
      text: _costPrice.toStringAsFixed(2),
    );
    _costFocusNode = FocusNode();
    _customExtraController = TextEditingController();
    _customExtraFocusNode = FocusNode();
    _scrollController = ScrollController();
    _speech = stt.SpeechToText();
    _initSpeech();
    _loadDailyUsage();
    _loadHistory();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              setState(() {
                _isListening = false;
                _soundLevel = 0.0;
                _spasmIntensity = 0.0;
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
            _soundLevel = 0.0;
            _spasmIntensity = 0.0;
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
    _pulseController.dispose();
    _costController.dispose();
    _costFocusNode.dispose();
    _brandController.dispose();
    _customExtraController.dispose();
    _customExtraFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LÓGICA DE DICTADO POR VOZ + RESPUESTA EN TIEMPO REAL + GEMINI
  // ---------------------------------------------------------------------------
  // ignore: unused_element
  Future<void> _toggleVoiceDictation() async {
    FocusScope.of(context).unfocus();

    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _soundLevel = 0.0;
        _spasmIntensity = 0.0;
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
      _soundLevel = 0.0;
      _spasmIntensity = 0.0;
      // Reiniciar bloqueos de sesión para esta nueva dictada
      _sessionCostLocked = false;
      _sessionExtraLocked = false;
      _sessionTypeLocked = false;
      _sessionCategoryLocked = false;
      _sessionSizesLocked = false;
    });

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'es_MX',
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 10),
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
      onSoundLevelChange: (level) {
        if (!mounted) return;
        // Normalizar volumen de la voz en dB (-2 a +10 aprox)
        final double normalized = ((level + 2.0) / 10.0).clamp(0.0, 1.0);
        _soundLevel = normalized;
        if (normalized > 0.18) {
          // Espasmo sutil y controlado, no desmedido
          _spasmIntensity = math.min(0.45, _spasmIntensity + normalized * 0.35);
        }
      },
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _spokenText = result.recognizedWords;
          // Pequeño espasmo sutil al detectar palabras en vivo
          _spasmIntensity = 0.45;
        });

        // ACTUALIZACIÓN EN TIEMPO REAL CON BLOQUEO PROGRESIVO
        _applyRealtimeExtraction(result.recognizedWords);
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

    final String? category = localData['categoria']?.toString();
    final String? type = localData['tipo']?.toString();
    final String name = localData['nombre_producto']?.toString() ?? '';
    final List<String> sizes =
        (localData['tallas'] as List?)?.map((e) => e.toString()).toList() ??
            [];
    final int? extra = localData['extra'] as int?;
    final bool noExtra = localData['no_extra'] == true;

    setState(() {
      // 1. Costo: Se bloquea en la sesión y NUNCA se sobreescribe con tallas o ruidos
      if (parsedCost != null && parsedCost > 0) {
        if (!_sessionCostLocked || _costPrice <= 0) {
          _costPrice = parsedCost;
          _costController.text = _costPrice.toStringAsFixed(2);
          _costCompleted = true;
          _sessionCostLocked = true; // Bloqueado contra sobreescritura
        }
      }

      // 2. Extra o "Sin Ganancia": Se bloquea en la sesión
      if (noExtra) {
        _selectedExtra = null;
        _customExtraController.clear();
        _extraCompleted = true;
        _sessionExtraLocked = true; // Bloqueado explícitamente sin ganancia
      } else if (extra != null && extra > 0) {
        if (!_sessionExtraLocked) {
          _selectedExtra = extra;
          if (!_extraOptions.contains(extra)) {
            _customExtraController.text = extra.toString();
          } else {
            _customExtraController.clear();
          }
          _extraCompleted = true;
          _sessionExtraLocked = true; // Bloqueado
        }
      }

      // 3. Tipo de producto
      if (type != null && type.isNotEmpty) {
        if (!_sessionTypeLocked) {
          if (type == 'prenda') {
            _selectedProductType = 'Prenda';
          } else if (type == 'tenis' ||
              type == 'tennis' ||
              name.toLowerCase().contains('tenis')) {
            _selectedProductType = 'Tenis';
          } else {
            _selectedProductType = 'Calzado';
          }
          _productTypeCompleted = true;
          _sessionTypeLocked = true; // Bloqueado
        }
      }

      if (name.isNotEmpty) {
        _customProductName = name;
      }

      // 4. Categoría
      if (category != null && category.isNotEmpty) {
        if (!_sessionCategoryLocked) {
          final c = category.toLowerCase();
          if (c.contains('caballero') || c.contains('hombre')) {
            _selectedCategory = 'Caballero';
          } else if (c.contains('niña') || c.contains('nina')) {
            _selectedCategory = 'Niña';
          } else if (c.contains('niño') ||
              c.contains('nino') ||
              c.contains('infantil')) {
            _selectedCategory = 'Niño';
          } else if (c.contains('junior')) {
            _selectedCategory = 'Juniors';
          } else if (c.contains('teen')) {
            _selectedCategory = 'Teens';
          } else if (c.contains('beba')) {
            _selectedCategory = 'Beba';
          } else if (c.contains('bebe') || c.contains('bebé')) {
            _selectedCategory = 'Bebé';
          } else if (c.contains('unisex')) {
            _selectedCategory = 'Unisex';
          } else if (c.contains('dama') || c.contains('mujer')) {
            _selectedCategory = 'Dama';
          }
          _categoryCompleted = true;
          _sessionCategoryLocked = true; // Bloqueado
        }
      }

      // 5. Tallas
      if (sizes.isNotEmpty) {
        _selectedSizes
          ..clear()
          ..addAll(sizes);
        _rangeFilled = sizes.length > 1;
        _sizeCompleted = true;
        _sessionSizesLocked = true;
      }
    });

    _checkAutoCloseIfComplete();
  }

  void _checkAutoCloseIfComplete() {
    if (_isAutoClosing) return;
    final bool hasCost = _sessionCostLocked && _costPrice > 0;
    final bool hasType = _selectedProductType != null;
    final bool hasCat = _selectedCategory != null;
    final bool hasSizes = _selectedSizes.isNotEmpty;

    // Cuando se tienen los 4 datos esenciales (Costo, Tipo, Categoría y Tallas) se cierra solo
    if (hasCost && hasType && hasCat && hasSizes) {
      _isAutoClosing = true;
      Future.delayed(const Duration(milliseconds: 1000), () async {
        if (!mounted) return;
        await _speech.stop();
        setState(() {
          _isListening = false;
        });
        if (_spokenText.trim().isNotEmpty && !_alreadyProcessedCurrentSpeech) {
          _alreadyProcessedCurrentSpeech = true;
          await _processTextWithGemini(_spokenText);
        }
        _isAutoClosing = false;
      });
    }
  }

  static const List<String> _geminiModelCandidates = [
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
  ];

  Future<GenerateContentResponse> _callGeminiWithFallback(
    List<Content> content,
  ) async {
    Object? lastError;
    for (final modelName in _geminiModelCandidates) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: _geminiApiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.1,
          ),
        );
        final response = await model.generateContent(content);
        final int tokens = response.usageMetadata?.totalTokenCount ?? 320;
        _recordAiUsage(tokens);
        return response;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('No se pudo conectar con Gemini');
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
      final prompt = '$_extractionPrompt\n\nTexto: "$spokenText"';
      final response =
          await _callGeminiWithFallback([Content.text(prompt)]);
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

  // ---------------------------------------------------------------------------
  // ESCANEO INTELIGENTE DE CAPTURAS DE CATÁLOGO (PRICE SHOES) CON GEMINI VISION
  // ---------------------------------------------------------------------------
  Future<void> _scanCatalogScreenshot() async {
    FocusScope.of(context).unfocus();
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 75,
    );
    if (pickedFile == null) return;

    if (_geminiApiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Falta configurar la API Key de Gemini en el archivo .env',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isScanningImage = true;
      _isProcessingAI = true;
      _isAutoClosing = false;
      _scanStatusMessage = 'Leyendo catálogo Price Shoes con IA...';
    });

    try {
      const String catalogPrompt = '''
Eres un asistente experto para extraer ofertas de capturas de pantalla de catálogos como Price Shoes y tiendas de calzado/ropa.
Analiza detenidamente la imagen y devuelve ÚNICAMENTE un JSON válido con esta estructura exacta:
{
  "marca": "Nike",
  "nombre_producto": "Tenis para correr Nike Stellar Ride (GS)",
  "tipo": "tenis",
  "categoria": "juniors",
  "precio_socio": 1249,
  "precio_promo": 1124,
  "tallas": []
}
Reglas estrictas:
- "marca": Nombre de la marca que aparece en la parte superior o en el nombre (ej. en "Nike - JUNIORS" la marca es "Nike"; ej. "Adidas", "Puma", "Pirma", "Charly", "Flexi", "Converse", "Vans", "Skechers", "Reebok", "Levis", etc.). Si no hay marca visible, pon "".
- "nombre_producto": Nombre completo del artículo o marca visible (ej. "Tenis Para Correr Nike Stellar Ride (GS)", "Tenis Charly", etc.).
- "tipo": 'tenis' (si son tenis, zapatillas deportivas o sneakers), 'calzado' (si son zapatos, botas, sandalias, tacones, pantuflas) o 'prenda' (si es ropa, blusa, playera, suéter, pantalón, etc.).
- "categoria": Extrae exactamente la categoría o público que aparece en el catálogo tal cual sale: 'dama', 'caballero', 'niño', 'niña', 'juniors', 'teens', 'bebe', 'beba' o 'unisex'. (Si dice JUNIORS o juniors, pon 'juniors'; si dice TEENS, 'teens'; si NIÑA, 'niña'; si NIÑO, 'niño'; si BEBE, 'bebe'; si BEBA, 'beba').
- "precio_socio": número exacto que acompaña a la palabra 'Socio' (ej. en 'Socio: \$1,249', extrae 1249). ¡IGNORA POR COMPLETO 'Al público'!.
- "precio_promo": número exacto que acompaña a 'Promo M' o precio de promoción (ej. en 'Promo M:\$1,124', extrae 1124). Si no hay promo, usa el mismo valor de precio_socio.
- "tallas": lista de strings de tallas si están visibles en la imagen (ej. ["22", "23"]); si no hay tallas visibles, devuelve [].
¡REGLA DE ORO!: NUNCA tomes el valor de 'Al público' ni números ajenos. Solo nos interesan EXCLUSIVAMENTE 'Socio' y 'Promo M'.
''';

      final imageBytes = await pickedFile.readAsBytes();
      final content = [
        Content.multi([
          TextPart(catalogPrompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ];

      final response = await _callGeminiWithFallback(content);
      final rawText = response.text ?? '';

      if (rawText.isNotEmpty) {
        final cleanedJson = rawText
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final decoded = jsonDecode(cleanedJson);

        if (decoded is Map<String, dynamic>) {
          final double socio = (decoded['precio_socio'] is num)
              ? (decoded['precio_socio'] as num).toDouble()
              : (double.tryParse(
                      decoded['precio_socio']?.toString().replaceAll(',', '') ??
                          '') ??
                  0.0);

          final double promo = (decoded['precio_promo'] is num)
              ? (decoded['precio_promo'] as num).toDouble()
              : (double.tryParse(
                      decoded['precio_promo']?.toString().replaceAll(',', '') ??
                          '') ??
                  socio);

          final String? tipoRaw = decoded['tipo']?.toString().toLowerCase();
          final String? catRaw = decoded['categoria']?.toString().toLowerCase();
          final String? nombreRaw = decoded['nombre_producto']?.toString();
          final String? marcaRaw = decoded['marca']?.toString();

          // Regla: 50% de ganancia con redondeo hacia arriba al múltiplo de 50 ("máxima ganancia")
          final double normalCalc = ((socio * 1.5) / 50.0).ceil() * 50.0;
          final double promoCalc = ((promo * 1.5) / 50.0).ceil() * 50.0;
          final double activeCost = promo > 0 ? promo : socio;
          final double base50 = activeCost * 1.5;
          final int extraDiff = math.max(0, (promoCalc - base50).round());

          String detectedType = 'Tenis';
          final nameLower = (nombreRaw ?? '').toLowerCase();
          final typeLower = (tipoRaw ?? '').toLowerCase();
          final marcaLower = (marcaRaw ?? '').toLowerCase();

          // Detección o respaldo de marca
          String detectedBrand = '';
          if (marcaRaw != null &&
              marcaRaw.trim().isNotEmpty &&
              marcaLower != 'null') {
            detectedBrand = marcaRaw.trim();
          } else {
            final commonBrands = [
              'Nike', 'Adidas', 'Puma', 'Pirma', 'Charly', 'Converse', 'Vans',
              'Reebok', 'Flexi', 'Skechers', 'Under Armour', 'Jordan', 'Fila',
              'Levis', 'Champion', 'K-Swiss', 'DC', 'Timberland', 'Crocs', 'Panam'
            ];
            for (final b in commonBrands) {
              if (nameLower.contains(b.toLowerCase())) {
                detectedBrand = b;
                break;
              }
            }
          }
          if (typeLower.contains('prenda') ||
              typeLower.contains('ropa') ||
              nameLower.contains('blusa') ||
              nameLower.contains('playera') ||
              nameLower.contains('pantalon') ||
              nameLower.contains('sueter') ||
              nameLower.contains('vestido') ||
              nameLower.contains('chamarra')) {
            detectedType = 'Prenda';
          } else if (typeLower.contains('tenis') ||
              typeLower.contains('tennis') ||
              nameLower.contains('tenis') ||
              nameLower.contains('tennis') ||
              nameLower.contains('sneaker') ||
              nameLower.contains('running')) {
            detectedType = 'Tenis';
          } else {
            detectedType = 'Calzado';
          }

          String detectedCat = 'Dama';
          if (catRaw != null) {
            final c = catRaw.trim().toLowerCase();
            if (c.contains('caballero') || c.contains('hombre')) {
              detectedCat = 'Caballero';
            } else if (c.contains('niña') || c.contains('nina')) {
              detectedCat = 'Niña';
            } else if (c.contains('niño') ||
                c.contains('nino') ||
                c.contains('infantil')) {
              detectedCat = 'Niño';
            } else if (c.contains('junior')) {
              detectedCat = 'Juniors';
            } else if (c.contains('teen')) {
              detectedCat = 'Teens';
            } else if (c.contains('beba')) {
              detectedCat = 'Beba';
            } else if (c.contains('bebe') ||
                c.contains('bebé') ||
                c.contains('maternal')) {
              detectedCat = 'Bebé';
            } else if (c.contains('unisex')) {
              detectedCat = 'Unisex';
            } else if (c.contains('dama') || c.contains('mujer')) {
              detectedCat = 'Dama';
            }
          }

          final List<dynamic>? rawSizes = decoded['tallas'] as List<dynamic>?;
          final List<String> parsedSizes = rawSizes
                  ?.map((e) => e.toString().trim())
                  .where((s) => s.isNotEmpty)
                  .toList() ??
              [];

          if (mounted) {
            setState(() {
              _selectedImage = null; // No guardar la captura como foto de producto
              _socioPrice = socio;
              _promoCost = promo;
              _costPrice = promo > 0 ? promo : socio;
              _costController.text = _costPrice.toStringAsFixed(2);
              _previousPrice = normalCalc > 0 ? normalCalc : null;
              _customOfferPrice = promoCalc > 0 ? promoCalc : null;

              _selectedExtra = extraDiff;
              if (_extraOptions.contains(extraDiff)) {
                _customExtraController.clear();
              } else {
                _customExtraController.text =
                    extraDiff > 0 ? extraDiff.toString() : '';
              }
              _extraCompleted = true;

              _selectedProductType = detectedType;
              _selectedCategory = detectedCat;
              _selectedBrand = detectedBrand.isNotEmpty ? detectedBrand : null;
              _brandController.text = _selectedBrand ?? '';
              if (nombreRaw != null && nombreRaw.trim().isNotEmpty) {
                _customProductName = nombreRaw.trim();
              }

              if (parsedSizes.isNotEmpty) {
                _selectedSizes.clear();
                _selectedSizes.addAll(parsedSizes);
                _sizeCompleted = true;
              }

              _costCompleted = true;
              _productTypeCompleted = true;
              _categoryCompleted = true;
              _photoCompleted = false;
              _scanStatusMessage =
                  '¡Catálogo detectado! Oferta calculada con éxito';
              _isAutoClosing = true;
            });

            await Future.delayed(const Duration(milliseconds: 900));
            if (mounted) {
              setState(() {
                _isProcessingAI = false;
                _isScanningImage = false;
                _isAutoClosing = false;
                _activeStep = 6; // Paso de foto
              });

              // Abre automáticamente la galería para que Sofía elija la foto limpia del calzado
              await Future.delayed(const Duration(milliseconds: 300));
              if (mounted) {
                await _pickPhotoFromGallery();
                if (mounted && _selectedImage != null) {
                  setState(() {
                    _activeStep = 7; // Oferta completada lista para compartir
                  });
                }
              }
            }
            return;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo analizar la captura: $e'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isProcessingAI = false;
        _isScanningImage = false;
        _isAutoClosing = false;
      });
    }
  }

  Map<String, dynamic> _extractNaturalLanguageLocal(String text) {
    final lower = text.toLowerCase();

    // 1. Categoría
    String? categoria;
    if (lower.contains('caballero') ||
        lower.contains('hombre') ||
        lower.contains('varón') ||
        lower.contains('varon')) {
      categoria = 'caballero';
    } else if (lower.contains('niña') || lower.contains('nina')) {
      categoria = 'niña';
    } else if (lower.contains('niño') ||
        lower.contains('nino') ||
        lower.contains('infantil')) {
      categoria = 'niño';
    } else if (lower.contains('junior')) {
      categoria = 'juniors';
    } else if (lower.contains('teen')) {
      categoria = 'teens';
    } else if (lower.contains('beba')) {
      categoria = 'beba';
    } else if (lower.contains('bebe') || lower.contains('bebé')) {
      categoria = 'bebe';
    } else if (lower.contains('unisex')) {
      categoria = 'unisex';
    } else if (lower.contains('dama') ||
        lower.contains('mujer') ||
        lower.contains('señora') ||
        lower.contains('senora')) {
      categoria = 'dama';
    }

    // 2. Tipo de producto y nombre específico
    String? tipo;
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
    } else if (lower.contains('tenis') || lower.contains('tennis')) {
      tipo = 'tenis';
    } else if (lower.contains('zapato') ||
        lower.contains('bota') ||
        lower.contains('sandalia') ||
        lower.contains('huarache') ||
        lower.contains('tacon') ||
        lower.contains('tacón') ||
        lower.contains('calzado')) {
      tipo = 'calzado';
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

    // 3. Tallas de calzado o prenda y recopilación de números para NO confundir con el precio
    final List<String> tallasCalzado = [];
    final List<String> tallasPrenda = [];
    final Set<int> sizeNumbersUsedInText = {};

    // Calzado numérico (ej. "corrida del 20 al 25", "del 20 al 25", "del 22 al 26")
    final rangeMatch = RegExp(
      r'(?:corrida\s+)?(?:del?|de\s+la|tallas?\s+de\s+la|tallas?\s+del?|tallas?)\s*(\d{1,2})(?:\.\d+)?\s*(?:al?|hasta\s+el|hasta\s+la)\s*(\d{1,2})(?:\.\d+)?',
    ).firstMatch(lower);

    if (rangeMatch != null) {
      final int start = int.parse(rangeMatch.group(1)!);
      final int end = int.parse(rangeMatch.group(2)!);
      final int minSize = start < end ? start : end;
      final int maxSize = start > end ? start : end;
      for (int s = minSize; s <= maxSize; s++) {
        sizeNumbersUsedInText.add(s);
      }
      if (minSize >= 10 && maxSize <= 34) {
        for (int s = minSize; s <= maxSize; s++) {
          tallasCalzado.add(s.toString());
        }
      }
    }

    // Tallas explícitas individuales (ej. "talla 24", "tallas 22 y 25")
    final explicitSizes = RegExp(r'\btallas?\s+(\d{1,2})\b').allMatches(lower);
    for (final m in explicitSizes) {
      final s = int.parse(m.group(1)!);
      sizeNumbersUsedInText.add(s);
      if (!tallasCalzado.contains(s.toString())) {
        tallasCalzado.add(s.toString());
      }
    }

    // Exclusión "menos el 23"
    final excludeMatch = RegExp(
      r'(?:menos|sin|excepto)\s+(?:el\s+|la\s+)?(\d{1,2})',
    ).allMatches(lower);
    for (final m in excludeMatch) {
      final String excluded = m.group(1)!;
      sizeNumbersUsedInText.add(int.parse(excluded));
      tallasCalzado.remove(excluded);
    }

    // Tallas de prenda (CH, M, G, XG, Unitalla)
    if (lower.contains('unitalla')) {
      tallasPrenda.add('Unitalla');
    } else {
      if (RegExp(r'(?:de\s+)?chica\s+(?:a|al?|hasta)\s+grande').hasMatch(lower)) {
        tallasPrenda.addAll(['CH', 'M', 'G']);
      } else if (RegExp(r'(?:de\s+)?chica\s+(?:a|al?|hasta)\s+extra\s*grande').hasMatch(lower)) {
        tallasPrenda.addAll(['CH', 'M', 'G', 'XG']);
      } else if (RegExp(r'(?:de\s+)?mediana\s+(?:a|al?|hasta)\s+grande').hasMatch(lower)) {
        tallasPrenda.addAll(['M', 'G']);
      } else {
        if (RegExp(r'\b(chica|chicas|ch)\b').hasMatch(lower)) {
          if (!tallasPrenda.contains('CH')) tallasPrenda.add('CH');
        }
        if (RegExp(r'\b(mediana|medianas|m)\b').hasMatch(lower)) {
          if (!tallasPrenda.contains('M')) tallasPrenda.add('M');
        }
        if (RegExp(r'\b(grande|grandes|g)\b').hasMatch(lower)) {
          if (!tallasPrenda.contains('G')) tallasPrenda.add('G');
        }
        if (RegExp(r'\b(extra\s*grande|extra\s*grandes|xg|xl)\b').hasMatch(lower)) {
          if (!tallasPrenda.contains('XG')) tallasPrenda.add('XG');
        }
      }
    }

    // Si el tipo es prenda, preferir tallas textiles; si es calzado, preferir números
    List<String> tallasFinales = [];
    final effectiveType = tipo ?? _selectedProductType?.toLowerCase() ?? 'calzado';
    if (effectiveType == 'prenda') {
      tallasFinales = tallasPrenda.isNotEmpty ? tallasPrenda : tallasCalzado;
    } else {
      tallasFinales = tallasCalzado.isNotEmpty ? tallasCalzado : tallasPrenda;
    }

    // 4. Ganancia extra o "Sin ganancia"
    int? extra;
    bool noExtraSpecified = false;
    if (RegExp(r'(?:no\s+quiero\s+(?:ganar|ganancia|ganancias)|sin\s+ganancia|cero\s+ganancia|nada\s+de\s+ganancia|sin\s+extra|no\s+le\s+ganes|sin\s+ganar)').hasMatch(lower)) {
      extra = 0;
      noExtraSpecified = true;
    } else {
      final extraMatch = RegExp(
        r'(?:ganar(?:le)?|ganancia|extra|sumar(?:le)?|más|mas)\s*(?:de\s*)?\$?\s*(\d{1,4})\b',
      ).firstMatch(lower);
      if (extraMatch != null) {
        extra = int.parse(extraMatch.group(1)!);
        sizeNumbersUsedInText.add(extra);
      }
    }

    // 5. Costo (Protegido para que NUNCA tome números de tallas)
    double? costo;
    final costoExplicitMatch = RegExp(
      r'(?:costó|costo|cuestan|cuesta|valen|vale|compré\s+en|compre\s+en|precio)\s*(?:es\s+de\s*|del?\s+.*?\s+cuesta\s*|de\s*)?\$?\s*(\d+(?:[.,]\d+)?)',
    ).firstMatch(lower);

    if (costoExplicitMatch != null) {
      final val = double.tryParse(
        costoExplicitMatch.group(1)!.replaceAll(',', '.'),
      );
      if (val != null && val > 0) {
        costo = val;
      }
    } else {
      // Solo buscar un número suelto si es mayor que 35 (para que NUNCA sea talla)
      // y que NO pertenezca a las tallas ni al extra
      final allNums = RegExp(r'\b\d+(?:[.,]\d+)?\b')
          .allMatches(lower)
          .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0.0)
          .where((n) => n > 35 && !sizeNumbersUsedInText.contains(n.round()))
          .toList();
      if (allNums.isNotEmpty) {
        costo = allNums.first;
      }
    }

    return {
      'costo': costo,
      'categoria': categoria,
      'extra': extra,
      'no_extra': noExtraSpecified,
      'tipo': tipo,
      'nombre_producto': nombreProducto,
      'tallas': tallasFinales,
    };
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  void _applyExtractedData(Map<String, dynamic> data) {
    final dynamic rawCost = data['costo'];
    final double? parsedCost = rawCost is num
        ? rawCost.toDouble()
        : double.tryParse(rawCost?.toString() ?? '');

    final String rawCategory =
        (data['categoria']?.toString() ?? '').toLowerCase().trim();
    String? mappedCategory;
    if (rawCategory.contains('caballero') || rawCategory.contains('hombre')) {
      mappedCategory = 'Caballero';
    } else if (rawCategory.contains('niña') || rawCategory.contains('nina')) {
      mappedCategory = 'Niña';
    } else if (rawCategory.contains('niño') ||
        rawCategory.contains('nino') ||
        rawCategory.contains('infantil')) {
      mappedCategory = 'Niño';
    } else if (rawCategory.contains('junior')) {
      mappedCategory = 'Juniors';
    } else if (rawCategory.contains('teen')) {
      mappedCategory = 'Teens';
    } else if (rawCategory.contains('beba')) {
      mappedCategory = 'Beba';
    } else if (rawCategory.contains('bebe') || rawCategory.contains('bebé')) {
      mappedCategory = 'Bebé';
    } else if (rawCategory.contains('unisex')) {
      mappedCategory = 'Unisex';
    } else if (rawCategory.contains('dama') || rawCategory.contains('mujer')) {
      mappedCategory = 'Dama';
    }

    final dynamic rawExtra = data['extra'];
    final int? parsedExtra = rawExtra is num
        ? rawExtra.round()
        : int.tryParse(rawExtra?.toString() ?? '');

    final String rawTipo =
        (data['tipo']?.toString() ?? '').toLowerCase().trim();
    final String customName =
        (data['nombre_producto']?.toString() ?? '').trim();
    final String rawMarca = (data['marca']?.toString() ?? '').trim();

    String detectedBrand = '';
    if (rawMarca.isNotEmpty && rawMarca.toLowerCase() != 'null') {
      detectedBrand = rawMarca;
    } else {
      final brands = [
        'Nike', 'Adidas', 'Puma', 'Pirma', 'Charly', 'Converse', 'Vans',
        'Reebok', 'Flexi', 'Skechers', 'Under Armour', 'Jordan', 'Fila',
        'Levis', 'Champion', 'K-Swiss', 'DC', 'Timberland', 'Crocs', 'Panam'
      ];
      final combined = '$customName $rawTipo'.toLowerCase();
      for (final b in brands) {
        if (combined.contains(b.toLowerCase())) {
          detectedBrand = b;
          break;
        }
      }
    }

    String? productType;
    if (rawTipo.contains('prenda') ||
        rawTipo.contains('ropa') ||
        customName.toLowerCase().contains('blusa') ||
        customName.toLowerCase().contains('playera') ||
        customName.toLowerCase().contains('pantalon') ||
        customName.toLowerCase().contains('sueter') ||
        customName.toLowerCase().contains('vestido')) {
      productType = 'Prenda';
    } else if (rawTipo.contains('tenis') ||
        rawTipo.contains('tennis') ||
        customName.toLowerCase().contains('tenis') ||
        customName.toLowerCase().contains('tennis') ||
        customName.toLowerCase().contains('sneaker')) {
      productType = 'Tenis';
    } else {
      productType = 'Calzado';
    }

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

      // 1. Costo: Si ya estaba bloqueado en la sesión, se preserva intacto
      if (_sessionCostLocked && _costPrice > 0) {
        // Se mantiene
      } else if (parsedCost != null && parsedCost > 0) {
        _costPrice = parsedCost;
        _costController.text = _costPrice.toStringAsFixed(2);
        _costCompleted = true;
      }

      // 2. Ganancia extra: Respetar si fue bloqueada sin ganancia o con ganancia
      if (_sessionExtraLocked) {
        // Se mantiene
      } else if (parsedExtra != null && parsedExtra > 0) {
        _selectedExtra = parsedExtra;
        if (!_extraOptions.contains(parsedExtra)) {
          _customExtraController.text = parsedExtra.toString();
        } else {
          _customExtraController.clear();
        }
        _extraCompleted = true;
      } else {
        _selectedExtra = null;
        _customExtraController.clear();
        _extraCompleted = true;
      }

      // 3. Producto
      if (detectedBrand.isNotEmpty) {
        _selectedBrand = detectedBrand;
        _brandController.text = detectedBrand;
      }
      if (_sessionTypeLocked && _selectedProductType != null) {
        if (customName.isNotEmpty) _customProductName = customName;
      } else if (productType != null) {
        _selectedProductType = productType;
        _customProductName = customName.isNotEmpty ? customName : null;
        _productTypeCompleted = true;
      }

      // 4. Categoría
      if (_sessionCategoryLocked && _selectedCategory != null) {
        // Se mantiene
      } else if (mappedCategory != null) {
        _selectedCategory = mappedCategory;
        _categoryCompleted = true;
      }

      // 5. Tallas
      if (extractedSizes.isNotEmpty) {
        _selectedSizes.clear();
        _selectedSizes.addAll(extractedSizes);
        _rangeFilled = extractedSizes.length > 1;
        _sizeCompleted = true;
        _activeStep = 6;
      } else if (!_sessionSizesLocked) {
        _selectedSizes.clear();
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

  // Fórmula: Costo + (Costo * 0.50) + GananciaExtra o Precio Oferta calculado por catálogo
  double get _baseProfit => _costPrice * 0.50;
  double get _totalProfit {
    if (_noProfitMode) {
      return math.max(0, _finalPrice - _costPrice);
    }
    return _customOfferPrice != null
        ? (_customOfferPrice! - _costPrice)
        : (_baseProfit + (_selectedExtra ?? 0));
  }

  double get _finalPrice {
    if (_noProfitMode) {
      return _basePriceRoundedTo10;
    }
    return _customOfferPrice ?? (_costPrice + _totalProfit);
  }

  List<String> get _currentSizeOptions {
    final String product = _selectedProductType ?? 'Tenis';
    final String category = _selectedCategory ?? 'Dama';

    List<String> baseList;
    if (product == 'Prenda') {
      if (category == 'Niño' || category == 'Niña') {
        baseList = List<String>.from(_ninoClothingSizes);
      } else if (category == 'Bebé' ||
          category == 'Bebe' ||
          category == 'Beba') {
        baseList = List<String>.from(_bebeClothingSizes);
      } else {
        baseList = List<String>.from(_adultClothingSizes);
      }
    } else {
      switch (category) {
        case 'Niña':
          baseList = List<String>.from(_ninaFootwearSizes);
          break;
        case 'Niño':
          baseList = List<String>.from(_ninoFootwearSizes);
          break;
        case 'Caballero':
          baseList = List<String>.from(_caballeroFootwearSizes);
          break;
        case 'Dama':
          baseList = List<String>.from(_damaFootwearSizes);
          break;
        case 'Juniors':
          baseList = List<String>.from(_juniorsFootwearSizes);
          break;
        case 'Teens':
          baseList = List<String>.from(_teensFootwearSizes);
          break;
        case 'Bebé':
        case 'Bebe':
          baseList = List<String>.from(_bebeFootwearSizes);
          break;
        case 'Beba':
          baseList = List<String>.from(_bebaFootwearSizes);
          break;
        case 'Unisex':
          baseList = List<String>.from(_unisexFootwearSizes);
          break;
        default:
          baseList = List<String>.from(_damaFootwearSizes);
          break;
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
    final String productLabel = _shortProductTypeLabel;
    final String category = _selectedCategory ?? 'Dama';
    final String title = _selectedCategory != null && _selectedCategory!.isNotEmpty
        ? '$productLabel $category'
        : productLabel;

    if (_previousPrice != null && _previousPrice! > 0) {
      final int prev = _previousPrice!.toInt();
      final int promo = _finalPrice.toInt();
      if (_selectedSizes.isNotEmpty) {
        return '$title precio anterior \$$prev precio de oferta \$$promo tallas $_sizesFormatted';
      }
      return '$title precio anterior \$$prev precio de oferta \$$promo';
    }

    final int price = _finalPrice.toInt();
    if (_selectedSizes.isNotEmpty) {
      return '$title precio de oferta \$$price tallas $_sizesFormatted';
    }
    return '$title precio de oferta \$$price';
  }

  void _clearAndFocusCost() {
    setState(() {
      _costController.clear();
      _costPrice = 0.0;
      _previousPrice = null;
      _customOfferPrice = null;
    });
    _costFocusNode.requestFocus();
  }

  void _resetAll() {
    _speech.stop();
    setState(() {
      _isListening = false;
      _isProcessingAI = false;
      _isScanningImage = false;
      _scanStatusMessage = '';
      _previousPrice = null;
      _socioPrice = null;
      _promoCost = null;
      _customOfferPrice = null;
      _noProfitMode = false;
      _spokenText = '';
      _costController.clear();
      _costPrice = 0.0;
      _selectedExtra = null;
      _customExtraController.clear();
      _selectedProductType = null;
      _selectedBrand = null;
      _brandController.clear();
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
      _sessionCostLocked = false;
      _sessionExtraLocked = false;
      _sessionTypeLocked = false;
      _sessionCategoryLocked = false;
      _sessionSizesLocked = false;
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
      _previousPrice = null;
      _customOfferPrice = null;
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
    FocusScope.of(context).unfocus();
    setState(() {
      if (_selectedExtra == amount) {
        _selectedExtra = null;
        _customExtraController.clear();
      } else {
        _selectedExtra = amount;
        _customExtraController.clear();
        _noProfitMode = false;
        _extraCompleted = true;
        _activeStep = 3;
      }
    });
  }

  void _onCustomExtraChanged(String value) {
    final cleanValue = value.trim();
    final int? parsed = int.tryParse(cleanValue);
    setState(() {
      if (parsed != null && parsed > 0) {
        _selectedExtra = parsed;
        _noProfitMode = false;
        _extraCompleted = true;
      } else {
        _selectedExtra = null;
      }
    });
  }

  void _clearCustomExtra() {
    _customExtraController.clear();
    setState(() {
      if (!_extraOptions.contains(_selectedExtra)) {
        _selectedExtra = null;
      }
    });
  }

  void _completeExtraStep() {
    FocusScope.of(context).unfocus();
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
      await _addOfferToHistory();
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
        await _addOfferToHistory();
        await Share.shareXFiles(
          [_selectedImage!],
          text: shareText,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isListeningActive = _isListening || _isProcessingAI;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isListeningActive
          ? const Color(0xFF030D06)
          : const Color(0xFFFBF9F4),
      appBar: isListeningActive
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              toolbarHeight: 52,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Calculadora AI',
                      style: TextStyle(
                        color: Color(0xFF1C1C1E),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _buildAppBarHistoryButton(),
                  const SizedBox(width: 6),
                  _buildAppBarQuotaChip(),
                ],
              ),
            ),
      body: isListeningActive
          ? _buildVoiceDictationOverlay()
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const SizedBox(height: 8),
                    _buildHistoryButton(),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTÓN DE HISTORIAL DE OFERTAS EN LA BARRA SUPERIOR
  // ---------------------------------------------------------------------------
  Widget _buildAppBarHistoryButton() {
    return Tooltip(
      message: 'Historial de ofertas guardadas',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showHistoryModal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F2ED),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: Color(0xFF3F3F46),
              ),
              if (_historyItems.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  '${_historyItems.length}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CHIP CONTADOR DE CONSULTAS/TOKENS GRATIS EN LA BARRA SUPERIOR
  // ---------------------------------------------------------------------------
  Widget _buildAppBarQuotaChip() {
    return Tooltip(
      message:
          'Consultas gratis hoy: $_remainingAiRequests / $_dailyFreeRequestsLimit',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showQuotaDialog,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFA5D6A7), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 15,
                color: Color(0xFF1B873F),
              ),
              const SizedBox(width: 2),
              Text(
                '$_remainingAiRequests',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B873F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuotaDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF1B873F), size: 26),
            SizedBox(width: 8),
            Text(
              'Cuota Gratis de IA',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google AI Studio te otorga 1,500 consultas diarias totalmente gratis sin ningún costo.',
              style: TextStyle(fontSize: 14, color: Color(0xFF3F3F46)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Consultas hoy:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$_todayAiRequestsUsed de $_dailyFreeRequestsLimit',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B873F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Disponibles hoy:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$_remainingAiRequests libres',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B873F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tokens hoy:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$_todayTokensUsed tokens',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF52525B),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Costo para Sofía:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '\$0.00 MXN',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1B873F),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'El contador se reinicia automáticamente cada día a las 00:00.',
              style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '¡Entendido!',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1B873F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MODAL Y BOTÓN DEL HISTORIAL DE OFERTAS
  // ---------------------------------------------------------------------------
  Widget _buildHistoryButton() {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: TextButton.icon(
        onPressed: _showHistoryModal,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF52525B),
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: Text(
          _historyItems.isEmpty
              ? 'Ver historial de ofertas'
              : 'Ver historial de ofertas (${_historyItems.length})',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _showHistoryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: const BoxDecoration(
              color: Color(0xFFFAF9F5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Encabezado del modal
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: Color(0xFF1B873F),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Historial de Ofertas',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF18181B),
                              ),
                            ),
                            Text(
                              '${_historyItems.length} ofertas registradas',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF71717A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_historyItems.isNotEmpty)
                        IconButton(
                          tooltip: 'Vaciar historial',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('¿Vaciar historial?'),
                                content: const Text(
                                  'Se eliminarán todas las ofertas guardadas de la lista.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx),
                                    child: const Text('Cancelar'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(dCtx);
                                      setState(() {
                                        _historyItems.clear();
                                      });
                                      setModalState(() {});
                                      await _saveHistoryToPrefs();
                                    },
                                    child: const Text(
                                      'Vaciar',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            color: Color(0xFF71717A),
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Lista de ofertas
                Expanded(
                  child: _historyItems.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 64,
                                  color: Color(0xFFD4D4D8),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Aún no hay ofertas en el historial',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF3F3F46),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Cada vez que calcules y compartas una oferta en WhatsApp, se guardará aquí automáticamente para consultar o volver a compartir.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF71717A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: _historyItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _historyItems[index];
                            final hasImage = item.imagePath != null &&
                                File(item.imagePath!).existsSync();
                            final dateFormatted =
                                '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')} ${item.date.hour.toString().padLeft(2, '0')}:${item.date.minute.toString().padLeft(2, '0')}';

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        child: hasImage
                                            ? Image.file(
                                                File(item.imagePath!),
                                                width: 54,
                                                height: 54,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 54,
                                                height: 54,
                                                color: const Color(0xFFF4F2ED),
                                                child: const Icon(
                                                  Icons.shopping_bag_outlined,
                                                  color: Color(0xFF71717A),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  '${item.productType} de ${item.category}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF18181B),
                                                  ),
                                                ),
                                                Text(
                                                  dateFormatted,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFFA1A1AA),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (item.previousPrice != null &&
                                                    item.previousPrice! > 0) ...[
                                                  Text(
                                                    '\$${item.previousPrice!.toInt()}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: Color(0xFF71717A),
                                                      decoration: TextDecoration
                                                          .lineThrough,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],
                                                Text(
                                                  '\$${item.finalPrice.toInt()}',
                                                  style: const TextStyle(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w900,
                                                    color: Color(0xFF16A34A),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFE8F5E9),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'Ganancia \$${item.profit.toInt()}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF1B873F),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F2ED),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.offerMessage,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF27272A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 36,
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                _shareHistoryItem(item),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF25D366),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.share_rounded,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Re-compartir en WhatsApp',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Eliminar oferta',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: Color(0xFFA1A1AA),
                                        ),
                                        onPressed: () async {
                                          setState(() {
                                            _historyItems.removeAt(index);
                                          });
                                          setModalState(() {});
                                          await _saveHistoryToPrefs();
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OVERLAY INMERSIVO EN PANTALLA COMPLETA CON ONDAS ORGÁNICAS (ESTILO NCS)
  // ---------------------------------------------------------------------------
  Widget _buildVoiceDictationOverlay() {
    final bool hasCost = _sessionCostLocked && _costPrice > 0;
    final bool hasTypeAndCat =
        _selectedProductType != null && _selectedCategory != null;
    final bool hasSizes = _selectedSizes.isNotEmpty;
    final bool hasExtra = _sessionExtraLocked || _selectedExtra != null;

    final String productCatText =
        _selectedProductType != null && _selectedCategory != null
            ? '$_shortProductTypeLabel $_selectedCategory'
            : (_selectedProductType != null
                ? _shortProductTypeLabel
                : (_selectedCategory ?? ''));

    return SizedBox.expand(
      child: Container(
        color: const Color(0xFF030D06), // Fondo 100% inmersivo sin huecos ni recuadros
        child: SafeArea(
              child: Column(
                children: [
                  // Encabezado superior con estado y botón X
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: _isAutoClosing
                                    ? const Color(0xFF00FF7F)
                                    : const Color(0xFF25D366),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00FF7F)
                                        .withValues(alpha: 0.9),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isAutoClosing
                                  ? '¡Todo listo! Completando...'
                                  : (_isScanningImage
                                      ? 'Analizando catálogo con IA...'
                                      : (_isProcessingAI
                                          ? 'Afinando detalles...'
                                          : 'Escuchando en vivo...')),
                              style: const TextStyle(
                                color: Color(0xFF00FF7F),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white60, size: 26),
                          onPressed: () async {
                            await _speech.stop();
                            setState(() {
                              _isListening = false;
                              _isProcessingAI = false;
                              _isScanningImage = false;
                              _isAutoClosing = false;
                              _soundLevel = 0.0;
                              _spasmIntensity = 0.0;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 1),

                  // ORBE INMERSIVO DE PLASMA Y ENERGÍA CON ESPASMOS REACTIVOS A LA VOZ
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      if (_spasmIntensity > 0.0) {
                        _spasmIntensity =
                            math.max(0.0, _spasmIntensity - 0.035);
                      }
                      return SizedBox(
                        width: 280,
                        height: 280,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(280, 280),
                              painter: PlasmaOrbPainter(
                                animationValue: _pulseController.value,
                                soundLevel: _soundLevel,
                                spasmIntensity: _spasmIntensity,
                                isListening: _isListening,
                                isComplete: _isAutoClosing,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.28),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00FF7F).withValues(
                                      alpha: (_isAutoClosing ? 0.9 : 0.45) +
                                          _spasmIntensity * 0.4,
                                    ),
                                    blurRadius: 18 + _spasmIntensity * 16,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isAutoClosing
                                    ? Icons.check_circle_rounded
                                    : (_isScanningImage
                                        ? Icons.document_scanner_rounded
                                        : Icons.mic_rounded),
                                size: 52,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const Spacer(flex: 1),

                  // Texto dictado o estado de escaneo en tiempo real
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _isScanningImage
                          ? _scanStatusMessage
                          : (_spokenText.isNotEmpty
                              ? '"$_spokenText"'
                              : 'Habla: ej. "zapato caballero cuesta 800 sin ganancia corrida del 20 al 25"...'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(
                            alpha: (_isScanningImage || _spokenText.isNotEmpty)
                                ? 1.0
                                : 0.65),
                        fontSize: (_isScanningImage || _spokenText.isNotEmpty)
                            ? 15
                            : 13.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color:
                                const Color(0xFF00FF7F).withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // LISTA QUE MUESTRA LO DETECTADO Y LO QUE FALTA (FROSTED EMERALD SIN MARCOS BLANCOS)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xCC061C0E),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFF114D28),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildRequirementRow(
                            isComplete: hasCost || (_previousPrice != null),
                            completeText: _previousPrice != null
                                ? 'Anterior: \$${_previousPrice!.toInt()} • Oferta: \$${_finalPrice.toInt()}'
                                : 'Costo: \$${_costPrice.toStringAsFixed(2)}',
                            pendingText: 'Falta: Costo (ej. cuesta 800)',
                            icon: Icons.attach_money_rounded,
                          ),
                          const Divider(color: Color(0xFF114D28), height: 16),
                          _buildRequirementRow(
                            isComplete: hasTypeAndCat,
                            completeText: productCatText,
                            pendingText:
                                'Falta: ¿Zapato o Ropa? ¿Dama, Caballero o Niño?',
                            icon: Icons.checkroom_rounded,
                          ),
                          const Divider(color: Color(0xFF114D28), height: 16),
                          _buildRequirementRow(
                            isComplete: hasSizes,
                            completeText: 'Tallas: $_sizesFormatted',
                            pendingText:
                                'Falta: Tallas (ej. corrida del 20 al 25)',
                            icon: Icons.straighten_rounded,
                            isOptional: _isScanningImage,
                          ),
                          const Divider(color: Color(0xFF114D28), height: 16),
                          _buildRequirementRow(
                            isComplete: _selectedImage != null || hasExtra,
                            completeText: _selectedImage != null
                                ? 'Foto de catálogo lista'
                                : (_selectedExtra != null
                                    ? 'Ganancia extra: +\$$_selectedExtra'
                                    : 'Sin ganancia extra'),
                            pendingText: _isScanningImage
                                ? 'Foto de producto asignada'
                                : 'Ganancia extra (Opcional)',
                            icon: _selectedImage != null
                                ? Icons.image_rounded
                                : Icons.add_chart_rounded,
                            isOptional: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildRequirementRow({
    required bool isComplete,
    required String completeText,
    required String pendingText,
    required IconData icon,
    bool isOptional = false,
  }) {
    return Row(
      children: [
        Icon(
          isComplete
              ? Icons.check_circle_rounded
              : (isOptional
                  ? Icons.info_outline_rounded
                  : Icons.radio_button_unchecked_rounded),
          size: 19,
          color: isComplete
              ? const Color(0xFF00FF7F)
              : (isOptional ? Colors.white38 : Colors.white60),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isComplete ? completeText : pendingText,
            style: TextStyle(
              color: isComplete
                  ? Colors.white
                  : (isOptional ? Colors.white38 : Colors.white70),
              fontSize: 13.5,
              fontWeight: isComplete ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
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
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _scanCatalogScreenshot,
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text(
                      'Escanear captura de Price Shoes',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1B873F),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. GANANCIA EXTRA (Opcional: 10, 20, 30, 40, 50 o personalizado)
  // ---------------------------------------------------------------------------
  Widget _buildExtraProfitCard() {
    final bool isExpanded = _activeStep == 2;
    final bool isCustomSelected =
        _selectedExtra != null && !_extraOptions.contains(_selectedExtra);

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
                    color: _noProfitMode
                        ? const Color(0xFFEFF6FF)
                        : (_selectedExtra != null
                            ? const Color(0xFFE0F5E9)
                            : const Color(0xFFEFECE6)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _noProfitMode
                        ? '+\$$_roundingTo10Extra (Al 10)'
                        : (_selectedExtra != null
                            ? '+\$$_selectedExtra'
                            : 'Opcional'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _noProfitMode
                          ? const Color(0xFF2563EB)
                          : (_selectedExtra != null
                              ? const Color(0xFF0A2E16)
                              : const Color(0xFF52525B)),
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
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                // Click para quitar ganancia extra y subir al 10
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _noProfitMode = !_noProfitMode;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _noProfitMode
                          ? const Color(0xFFEFF6FF)
                          : const Color(0xFFF4F2ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _noProfitMode
                            ? const Color(0xFF3B82F6)
                            : Colors.transparent,
                        width: 1.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _noProfitMode
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: _noProfitMode
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF71717A),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sin ganancia extra (solo al 10)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: _noProfitMode
                                      ? const Color(0xFF1E40AF)
                                      : const Color(0xFF18181B),
                                ),
                              ),
                              Text(
                                _noProfitMode
                                    ? 'Activo: Mantiene el 50% y solo sube +\$$_roundingTo10Extra para llegar a \$${_basePriceRoundedTo10.toInt()}'
                                    : 'Mantiene tu 50% y solo añade los pesos necesarios para terminar en 10',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: _noProfitMode
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF71717A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Fila con los 5 botones preestablecidos: 10, 20, 30, 40, 50
                Row(
                  children: _extraOptions.map((amount) {
                    final bool isSelected = _selectedExtra == amount;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _toggleExtraOption(amount),
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
                              '+\$$amount',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? const Color(0xFF18181B)
                                    : const Color(0xFF3F3F46),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                // Opción abajo para escribir otro monto diferente
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCustomSelected
                        ? Colors.white
                        : const Color(0xFFF4F2ED),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCustomSelected
                          ? const Color(0xFF7CA6F8)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 20,
                        color: isCustomSelected
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF71717A),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Otro monto: +',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isCustomSelected
                              ? const Color(0xFF18181B)
                              : const Color(0xFF3F3F46),
                        ),
                      ),
                      const Text(
                        '\$',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF18181B),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _customExtraController,
                          focusNode: _customExtraFocusNode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18181B),
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Ej. 25, 60...',
                            hintStyle: TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: _onCustomExtraChanged,
                        ),
                      ),
                      if (_customExtraController.text.isNotEmpty)
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _clearCustomExtra,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.cancel,
                              size: 18,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        ),
                    ],
                  ),
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
                      _noProfitMode
                          ? 'Siguiente (\$${_basePriceRoundedTo10.toInt()} al 10)'
                          : (_selectedExtra == null
                              ? 'Omitir paso'
                              : 'Siguiente (+\$$_selectedExtra)'),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF27272A),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. TIPO DE PRODUCTO (Calzado / Prenda)
  // ---------------------------------------------------------------------------
  Widget _buildProductTypeCard() {
    final bool isExpanded = _activeStep == 3;
    final List<String> productTypes = ['Tenis', 'Calzado', 'Prenda'];

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
                const Text(
                  '3. Tipo de producto',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const Spacer(),
                if (_selectedProductType != null) ...[
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F5E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _shortProductTypeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0A2E16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
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
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 10),
                // Campo para marca detectada o manual
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F2ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sell_outlined,
                        size: 18,
                        color: Color(0xFF71717A),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Marca:',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3F3F46),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _brandController,
                          onChanged: (val) {
                            setState(() {
                              _selectedBrand =
                                  val.trim().isNotEmpty ? val.trim() : null;
                            });
                          },
                          decoration: const InputDecoration(
                            hintText: 'Ej. Nike, Adidas, Pirma...',
                            hintStyle: TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18181B),
                          ),
                        ),
                      ),
                      if (_brandController.text.isNotEmpty)
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _brandController.clear();
                              _selectedBrand = null;
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.cancel,
                              size: 16,
                              color: Color(0xFFA1A1AA),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Chips de marcas comunes para selección rápida
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    'Nike',
                    'Adidas',
                    'Puma',
                    'Pirma',
                    'Charly',
                    'Flexi',
                    'Vans',
                    'Converse'
                  ].map((brand) {
                    final bool isSelected =
                        _selectedBrand?.toLowerCase() == brand.toLowerCase();
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedBrand = null;
                            _brandController.clear();
                          } else {
                            _selectedBrand = brand;
                            _brandController.text = brand;
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF18181B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF18181B)
                                : const Color(0xFFE4E4E7),
                          ),
                        ),
                        child: Text(
                          brand,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF3F3F46),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. CATEGORÍA (Dama / Caballero / Niño)
  // ---------------------------------------------------------------------------
  Widget _buildCategoryCard() {
    final bool isExpanded = _activeStep == 4;
    final List<String> categories = [
      'Dama',
      'Caballero',
      'Niño',
      'Niña',
      'Juniors',
      'Teens',
      'Bebé',
      'Beba',
      'Unisex',
    ];

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
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((label) {
                    final bool isSelected = _selectedCategory == label;

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectCategory(label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
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
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: const Color(0xFF18181B),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
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
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                                  side: const BorderSide(
                                      color: Color(0xFFD4D4D8)),
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
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
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
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRECIO FINAL Y VISTA PREVIA DEL MENSAJE
  // ---------------------------------------------------------------------------
  Widget _buildFinalPriceCard() {
    final bool hasPrev = _previousPrice != null && _previousPrice! > 0;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasPrev ? 'Oferta de Catálogo' : 'Precio Final',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              // Botón rápido para quitar la ganancia (click al 10)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    _noProfitMode = !_noProfitMode;
                    if (_noProfitMode) {
                      _selectedExtra = null;
                      _customExtraController.clear();
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _noProfitMode
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF4F2ED),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _noProfitMode
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFFE4E4E7),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _noProfitMode
                            ? Icons.check_circle_rounded
                            : Icons.remove_circle_outline_rounded,
                        size: 15,
                        color: _noProfitMode
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF71717A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _noProfitMode ? 'Sin extra (al 10)' : 'Quitar extra',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _noProfitMode
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF71717A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _noProfitMode
                      ? const Color(0xFFEFF6FF)
                      : (hasPrev
                          ? const Color(0xFF63FF83)
                          : const Color(0xFFE8F5E9)),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    if (hasPrev && !_noProfitMode)
                      BoxShadow(
                        color: const Color(0xFF63FF83).withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Text(
                  _noProfitMode
                      ? 'Al 10'
                      : (hasPrev ? 'Promo M' : 'Sugerido'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _noProfitMode
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF0A2E16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey<String>(
                'final_price_${_finalPrice.toInt()}_${_previousPrice?.toInt() ?? 0}_${_shortProductTypeLabel}_$_noProfitMode',
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F2ED),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  if (hasPrev) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Precio anterior: \$${_previousPrice!.toInt()}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF71717A),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Ahorro \$${(_previousPrice! - _finalPrice).toInt()}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    '\$ ${_finalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasPrev
                        ? 'Socio \$${_socioPrice?.toInt() ?? 0} • Promo M \$${_promoCost?.toInt() ?? _costPrice.toInt()} • Ganancia \$${_totalProfit.toStringAsFixed(0)}'
                        : 'Costo \$${_costPrice.toStringAsFixed(2)} + Ganancia \$${_totalProfit.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF52525B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    child: Text(
                      _generatedOfferMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF18181B),
                      ),
                    ),
                  ),
                ],
              ),
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

class OfferHistoryItem {
  final String id;
  final DateTime date;
  final String productType;
  final String category;
  final double cost;
  final double? previousPrice;
  final double finalPrice;
  final double profit;
  final String offerMessage;
  final String? imagePath;
  final List<String> sizes;

  OfferHistoryItem({
    required this.id,
    required this.date,
    required this.productType,
    required this.category,
    required this.cost,
    this.previousPrice,
    required this.finalPrice,
    required this.profit,
    required this.offerMessage,
    this.imagePath,
    this.sizes = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'productType': productType,
        'category': category,
        'cost': cost,
        'previousPrice': previousPrice,
        'finalPrice': finalPrice,
        'profit': profit,
        'offerMessage': offerMessage,
        'imagePath': imagePath,
        'sizes': sizes,
      };

  factory OfferHistoryItem.fromJson(Map<String, dynamic> json) =>
      OfferHistoryItem(
        id: json['id']?.toString() ?? '',
        date: DateTime.tryParse(json['date']?.toString() ?? '') ??
            DateTime.now(),
        productType: json['productType']?.toString() ?? 'Tenis',
        category: json['category']?.toString() ?? 'Dama',
        cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
        previousPrice: (json['previousPrice'] as num?)?.toDouble(),
        finalPrice: (json['finalPrice'] as num?)?.toDouble() ?? 0.0,
        profit: (json['profit'] as num?)?.toDouble() ?? 0.0,
        offerMessage: json['offerMessage']?.toString() ?? '',
        imagePath: json['imagePath']?.toString(),
        sizes: (json['sizes'] as List?)?.map((e) => e.toString()).toList() ??
            [],
      );
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

/// Visualizador inmersivo de orbe de energía y luz: relajado, sereno y con
/// pequeños espasmos sutiles y reactivos únicamente cuando se habla.
class PlasmaOrbPainter extends CustomPainter {
  final double animationValue; // 0.0 a 1.0 lineal
  final double soundLevel; // 0.0 a 1.0
  final double spasmIntensity; // 0.0 a 0.5 (pequeños espasmos reactivos a la voz)
  final bool isListening;
  final bool isComplete;

  PlasmaOrbPainter({
    required this.animationValue,
    required this.soundLevel,
    required this.spasmIntensity,
    required this.isListening,
    required this.isComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double baseR = size.width * 0.31; // ~86px

    // Respiración serena y relajada (lenta y suave)
    final double calmBreathe = math.sin(animationValue * 2 * math.pi) * 2.5;

    // Reactividad sutil controlada (pequeños espasmos, no exagerados)
    final double subtleSpasm = isComplete
        ? 0.0
        : (spasmIntensity * 0.8 + soundLevel * 0.3).clamp(0.0, 0.6);
    final double spasmJitter = isComplete
        ? 0.0
        : (math.sin(animationValue * 24 * math.pi) * 2.0 * spasmIntensity);

    // 1. AURA EXTERIOR SUAVE Y DIFUMINADA (Brillo esmeralda relajante)
    final double auraRadius = baseR * 1.45 + calmBreathe + (subtleSpasm * 12.0);
    final Paint auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          (isComplete ? const Color(0xFF00FF7F) : const Color(0xFF00FF88))
              .withValues(alpha: (0.35 + subtleSpasm * 0.25).clamp(0.0, 1.0)),
          const Color(0xFF00E676)
              .withValues(alpha: (0.12 + subtleSpasm * 0.1).clamp(0.0, 1.0)),
          const Color(0xFF003318).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: auraRadius));
    canvas.drawCircle(center, auraRadius, auraPaint);

    // 2. ONDA DE CHOQUE SUAVE Y LENTA (1 onda tenue periódica)
    final double wavePhase = animationValue % 1.0;
    final double waveRadius = baseR * 0.8 + wavePhase * (baseR * 0.55);
    final double waveAlpha =
        (1.0 - wavePhase).clamp(0.0, 1.0) * (0.2 + subtleSpasm * 0.25);
    if (waveAlpha > 0.02) {
      final Paint wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF00FF7F)
            .withValues(alpha: waveAlpha.clamp(0.0, 1.0));
      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // 3. ANILLOS ORGÁNICOS SUAVES (Curvas armónicas tranquilas con micro-espasmos solo al hablar)
    _drawCalmWaveRing(
      canvas: canvas,
      center: center,
      radius: baseR * 1.08 + calmBreathe,
      harmonic: 5,
      speed: 2.0,
      baseAmplitude: 2.0,
      spasmExtra: subtleSpasm * 4.5,
      jitter: spasmJitter,
      color: const Color(0xFF00FF88),
      alpha: 0.65 + subtleSpasm * 0.2,
      strokeWidth: 2.0,
    );

    _drawCalmWaveRing(
      canvas: canvas,
      center: center,
      radius: baseR * 0.92 - calmBreathe * 0.5,
      harmonic: 7,
      speed: -2.5,
      baseAmplitude: 1.5,
      spasmExtra: subtleSpasm * 3.5,
      jitter: -spasmJitter * 0.6,
      color: const Color(0xFF69F0AE),
      alpha: 0.75,
      strokeWidth: 1.8,
    );

    // 4. MICRO-ESPASMO ELÉCTRICO SUTIL (Únicamente cuando se habla)
    if (!isComplete && spasmIntensity > 0.15) {
      _drawSubtleElectricSpasm(canvas, center, baseR, subtleSpasm);
    }

    // 5. CHISPAS DE POLVO LUMINOSO FLOTANDO SERENAS
    _drawGentleParticles(canvas, center, baseR, subtleSpasm);

    // 6. NÚCLEO LUMINOSO SUAVE (Centro radiante acogedor)
    final double coreR =
        baseR * 0.52 + (calmBreathe * 0.8) + (subtleSpasm * 8.0);
    final Paint corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          const Color(0xFFE8FFF3),
          const Color(0xFF00FF7F).withValues(alpha: 0.8),
          const Color(0xFF00E676).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreR));
    canvas.drawCircle(center, coreR, corePaint);

    // Destello interior sutil
    final Paint whiteCenter = Paint()
      ..color = Colors.white
          .withValues(alpha: (0.65 + subtleSpasm * 0.25).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, coreR * 0.38, whiteCenter);
  }

  void _drawCalmWaveRing({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required int harmonic,
    required double speed,
    required double baseAmplitude,
    required double spasmExtra,
    required double jitter,
    required Color color,
    required double alpha,
    required double strokeWidth,
  }) {
    final Path path = Path();
    const int segments = 80;
    const double step = (math.pi * 2) / segments;

    for (int i = 0; i <= segments; i++) {
      final double theta = i * step;
      // Ondulación senoidal suave y relajada
      final double wave =
          math.sin(theta * harmonic + animationValue * speed * math.pi);
      // Pequeño micro-espasmo armónico sólo cuando se habla
      final double microSpasm =
          math.sin(theta * 17 + animationValue * 18 * math.pi) * spasmExtra;
      final double r = radius + wave * baseAmplitude + microSpasm + jitter;

      final double x = center.dx + r * math.cos(theta);
      final double y = center.dy + r * math.sin(theta);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Resplandor suave del borde
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.2
      ..color = color.withValues(alpha: (alpha * 0.35).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    // Borde armónico
    final Paint linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas.drawPath(path, linePaint);
  }

  void _drawSubtleElectricSpasm(
    Canvas canvas,
    Offset center,
    double baseR,
    double subtleSpasm,
  ) {
    // Solo 1 o 2 filamentos muy delicados, delgados y breves
    const int filaments = 2;
    for (int f = 0; f < filaments; f++) {
      final double angle = (f * math.pi) +
          (animationValue * 2.0 * math.pi) +
          (math.sin(f * 2.5 + animationValue * 8) * 0.3);

      final double startDist = baseR * 0.4;
      final double endDist = baseR * (1.02 + subtleSpasm * 0.12);

      final Offset start = Offset(
        center.dx + startDist * math.cos(angle),
        center.dy + startDist * math.sin(angle),
      );
      final Offset end = Offset(
        center.dx + endDist * math.cos(angle + 0.2),
        center.dy + endDist * math.sin(angle + 0.2),
      );

      final Path p = Path();
      p.moveTo(start.dx, start.dy);
      const int steps = 5;
      final double dx = (end.dx - start.dx) / steps;
      final double dy = (end.dy - start.dy) / steps;
      final double len = math.sqrt(dx * dx + dy * dy);
      final double nx = -dy / (len > 0 ? len : 1);
      final double ny = dx / (len > 0 ? len : 1);

      for (int s = 1; s < steps; s++) {
        final double jitter =
            math.sin((f * 13.0) + (s * 3.7) + (animationValue * 25)) *
                (2.5 * subtleSpasm * (1.0 - (s / steps - 0.5).abs()));
        p.lineTo(
            start.dx + dx * s + nx * jitter, start.dy + dy * s + ny * jitter);
      }
      p.lineTo(end.dx, end.dy);

      final Paint filamentPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white
            .withValues(alpha: (0.8 * subtleSpasm).clamp(0.0, 1.0))
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(p, filamentPaint);
    }
  }

  void _drawGentleParticles(
    Canvas canvas,
    Offset center,
    double baseR,
    double subtleSpasm,
  ) {
    const int count = 16;
    for (int i = 0; i < count; i++) {
      final double pAngle = (i * 2.39996) +
          (animationValue * (0.8 + (i % 3) * 0.2) * math.pi);
      final double pDist = baseR * 0.5 + ((i * 11.3) % (baseR * 0.7));
      final double px = center.dx + pDist * math.cos(pAngle);
      final double py = center.dy + pDist * math.sin(pAngle);
      final double pSize = 1.2 + (i % 2) * 0.6;
      final double pAlpha =
          (0.35 + (math.sin(pAngle * 2 + animationValue * 4) * 0.2))
              .clamp(0.1, 0.7);

      final Paint pPaint = Paint()
        ..color = const Color(0xFF00FF7F).withValues(alpha: pAlpha);
      canvas.drawCircle(Offset(px, py), pSize, pPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PlasmaOrbPainter oldDelegate) {
    return true;
  }
}

// Compatibilidad por si se llama con el nombre anterior
typedef WavyVisualizerPainter = PlasmaOrbPainter;
