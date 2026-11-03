import 'package:flutter_test/flutter_test.dart';
import 'package:calculadora_ofertas/main.dart';

void main() {
  testWidgets('Calculadora de Ofertas smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CalculadoraOfertasApp());
    expect(find.text('Calculadora For Status Whatsapp'), findsOneWidget);
  });
}
