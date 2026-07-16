import 'package:flutter/material.dart';
import 'package:lemon_x/lemon_x.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LemonApp(
      bindings: (container) {
        container.lazyPut(() => CounterController());
      },
      child: const MaterialApp(home: CounterPage()),
    );
  }
}

class CounterController extends LxController {
  final count = 0.obs;

  void increment() => count.value++;
}

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.lx.find<CounterController>();

    return Scaffold(
      appBar: AppBar(title: const Text('LemonX')),
      body: Center(
        child: Obx(
          () => Text(
            '${controller.count.value}',
            style: Theme.of(context).textTheme.displayMedium,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
