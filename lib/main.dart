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
- "categoria": únicamente 'dama', 'caballero' o 'niño'.
- "extra": número de ganancia adicional si la menciona (ej. 10, 20, 25, 30, 40, 50, etc.). Si dice "no quiero ganar ganancias", "sin ganancia", o no menciona ganancia, pon 0.
- "tipo": 'calzado' (si habla de tenis, zapatos, botas, sandalias, huaraches, corrida numérica) o 'prenda' (si habla de ropa, suéter, blusa, pantalón, camisa, playera, vestido).
- "nombre_producto": si menciona marca o artículo específico (ej. "Tenis Pirma", "Suéter", "Blusa"), ponlo con inicial mayúscula; si no, pon "".
- "tallas": lista de strings de tallas.
  * Para calzado: tallas individuales enteras numéricas (ej. ["20", "21", "22", "23", "24", "25"]).
  * Para prendas: usa ÚNICAMENTE ["CH", "M", "G", "XG", "Unitalla"] si dice chica, mediana, grande, extra grande o unitalla. Si dice "de chica a grande", pon ["CH", "M", "G"].
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
  late final AnimationController _pulseController;
  bool _isAutoClosing = false;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isProcessingAI = false;
  String _spokenText = '';
  bool _alreadyProcessedCurrentSpeech = false;
  double _soundLevel = 0.0;
  double _spasmIntensity = 0.0;

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

  final List<String> _damaFootwearSizes = [
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
  ];

  final List<String> _caballeroFootwearSizes = [
    '20',
    '21',
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
    _customExtraController = TextEditingController();
    _customExtraFocusNode = FocusNode();
    _scrollController = ScrollController();
    _speech = stt.SpeechToText();
    _initSpeech();
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
    _customExtraController.dispose();
    _customExtraFocusNode.dispose();
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
          _selectedProductType = type == 'prenda' ? 'Prenda' : 'Calzado';
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
          if (category == 'caballero') _selectedCategory = 'Caballero';
          if (category == 'niño') _selectedCategory = 'Niño';
          if (category == 'dama') _selectedCategory = 'Dama';
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
    String? categoria;
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
    } else if (lower.contains('zapato') ||
        lower.contains('tenis') ||
        lower.contains('tennis') ||
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
    if (rawCategory.contains('caballero')) {
      mappedCategory = 'Caballero';
    } else if (rawCategory.contains('niñ') || rawCategory.contains('nin')) {
      mappedCategory = 'Niño';
    } else if (rawCategory.contains('dama')) {
      mappedCategory = 'Dama';
    }

    final dynamic rawExtra = data['extra'];
    final int? parsedExtra = rawExtra is num
        ? rawExtra.round()
        : int.tryParse(rawExtra?.toString() ?? '');

    final String rawTipo =
        (data['tipo']?.toString() ?? '').toLowerCase().trim();
    final String? productType = rawTipo.contains('prenda')
        ? 'Prenda'
        : (rawTipo.contains('calzado') ? 'Calzado' : null);

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
      _customExtraController.clear();
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
                      'Calculadora For Status Whatsapp',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF1C1C1E),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildAppBarMicButton(),
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
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTÓN DE MICRÓFONO COMPACTO EN LA BARRA SUPERIOR (JUNTO A WHATSAPP)
  // ---------------------------------------------------------------------------
  Widget _buildAppBarMicButton() {
    final bool isActive = _isListening || _isProcessingAI;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: _toggleVoiceDictation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1B873F) : const Color(0xFFE8F5E9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF25D366)
                  .withValues(alpha: isActive ? 0.45 : 0.15),
              blurRadius: isActive ? 10 : 4,
              spreadRadius: isActive ? 2 : 0,
            ),
          ],
        ),
        child: Icon(
          _isListening
              ? Icons.mic_rounded
              : _isProcessingAI
                  ? Icons.hourglass_top_rounded
                  : Icons.mic_none_rounded,
          size: 22,
          color: isActive ? Colors.white : const Color(0xFF1B873F),
        ),
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
            ? '${_customProductName ?? _selectedProductType!} de $_selectedCategory'
            : (_selectedProductType != null
                ? (_customProductName ?? _selectedProductType!)
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
                                  : (_isProcessingAI
                                      ? 'Afinando detalles...'
                                      : 'Escuchando en vivo...'),
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
                                    : Icons.mic_rounded,
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

                  // Texto dictado en tiempo real sin recuadros blancos rígidos
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _spokenText.isNotEmpty
                          ? '"$_spokenText"'
                          : 'Habla: ej. "zapato caballero cuesta 800 sin ganancia corrida del 20 al 25"...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(
                            alpha: _spokenText.isNotEmpty ? 1.0 : 0.65),
                        fontSize: _spokenText.isNotEmpty ? 16 : 13.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF00FF7F).withValues(alpha: 0.4),
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
                            isComplete: hasCost,
                            completeText:
                                'Costo: \$${_costPrice.toStringAsFixed(2)}',
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
                          ),
                          const Divider(color: Color(0xFF114D28), height: 16),
                          _buildRequirementRow(
                            isComplete: hasExtra,
                            completeText: _selectedExtra != null
                                ? 'Ganancia extra: +\$$_selectedExtra'
                                : 'Sin ganancia extra',
                            pendingText: 'Ganancia extra (Opcional)',
                            icon: Icons.add_chart_rounded,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:
                    isCustomSelected ? Colors.white : const Color(0xFFF4F2ED),
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
                  _selectedExtra == null
                      ? 'Omitir paso'
                      : 'Siguiente (+\$$_selectedExtra)',
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
