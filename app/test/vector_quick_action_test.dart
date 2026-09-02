import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/vector_quick_action.dart';

void main() {
  test('recognizes only the Vector add-purchase control link', () {
    expect(
      isVectorAddPurchaseLink(Uri.parse('moneylock://vector/add')),
      isTrue,
    );
    expect(
      isVectorAddPurchaseLink(Uri.parse('moneylock://add?amount=20')),
      isFalse,
    );
    expect(
      isVectorAddPurchaseLink(
        Uri.parse('https://moneylock.example/vector/add'),
      ),
      isFalse,
    );
  });

  test('quick action is delivered once after navigation becomes available', () {
    final controller = VectorQuickActionController();
    controller.requestAddPurchase();

    expect(controller.takePending(), VectorQuickAction.addPurchase);
    expect(controller.takePending(), isNull);
  });
}
