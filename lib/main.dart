import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

void main() {
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
  double _costPrice = 25.00;
  int? _selectedExtra; // Opcional
  String? _selectedCategory;
  XFile? _selectedImage;

  // Paso activo: 1 = Costo, 2 = Ganancia extra, 3 = Categoría, 4 = Foto, 5 = Completado
  int _activeStep = 1;
  bool _costCompleted = false;
  bool _extraCompleted = false;
  bool _categoryCompleted = false;
  bool _photoCompleted = false;

  late final TextEditingController _costController;
  late final FocusNode _costFocusNode;
  late final ScrollController _scrollController;
  final ImagePicker _picker = ImagePicker();

  final List<int> _extraOptions = [10, 15, 20, 30];

  @override
  void initState() {
    super.initState();
    _costController = TextEditingController(
      text: _costPrice.toStringAsFixed(2),
    );
    _costFocusNode = FocusNode();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _costController.dispose();
    _costFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fórmula: Costo + (Costo / 2) + GananciaExtra
  double get _baseProfit => _costPrice / 2.0;
  double get _totalProfit => _baseProfit + (_selectedExtra ?? 0);
  double get _finalPrice => _costPrice + _totalProfit;

  void _clearAndFocusCost() {
    setState(() {
      _costController.clear();
      _costPrice = 0.0;
    });
    _costFocusNode.requestFocus();
  }

  void _resetAll() {
    setState(() {
      _costController.clear();
      _costPrice = 0.0;
      _selectedExtra = null;
      _selectedCategory = null;
      _selectedImage = null;
      _costCompleted = false;
      _extraCompleted = false;
      _categoryCompleted = false;
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

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _categoryCompleted = true;
      _activeStep = 4;
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
          _activeStep = 5;
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
    final String categoryLabel = _selectedCategory ?? 'Dama';
    final String shareText =
        'Zapato de $categoryLabel precio de oferta \$${_finalPrice.toStringAsFixed(2)}';

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
        _activeStep = 4;
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
              _buildCostCard(),
              const SizedBox(height: 10),
              _buildExtraProfitCard(),
              const SizedBox(height: 10),
              _buildCategoryCard(),
              const SizedBox(height: 10),
              _buildPhotoCard(),
              const SizedBox(height: 12),
              _buildFinalPriceCard(),
              const SizedBox(height: 14),
              _buildShareButton(),
              const SizedBox(height: 10),
              _buildClearButton(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. COSTO DEL ZAPATO
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
                    '1. Costo del zapato',
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
  // 3. TIPO DE CALZADO
  // ---------------------------------------------------------------------------
  Widget _buildCategoryCard() {
    final bool isExpanded = _activeStep == 3;
    final List<String> categories = ['Dama', 'Caballero', 'Niño'];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 3),
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
                    '3. Tipo de calzado',
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
  // 4. FOTO DEL CALZADO (Solo Galería)
  // ---------------------------------------------------------------------------
  Widget _buildPhotoCard() {
    final bool isExpanded = _activeStep == 4;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _activeStep = isExpanded ? 0 : 4),
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
                    '4. Foto del calzado',
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
  // PRECIO FINAL
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
  // BOTÓN LIMPIAR ("Limpiar" - Borra todo y regresa al costo para escribir rápido)
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
