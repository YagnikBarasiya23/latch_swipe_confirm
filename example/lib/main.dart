import 'package:flutter/material.dart';
import 'package:latch_swipe_confirm/latch_swipe_confirm.dart';

void main() => runApp(const LatchDemo());

const _bg = Color(0xFF050505);
const _panel = Color(0xFF0E0E10);
const _line = Color(0x1AFFFFFF);
const _muted = Color(0xFFA1A1AA);
const _accent = Color(0xFFD9F99D);
const _danger = Color(0xFFF87171);

class LatchDemo extends StatelessWidget {
  const LatchDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Latch — swipe to confirm for Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _panel),
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  bool _failNext = false;
  int _round = 0;
  String _log = 'Nothing yet — swipe one of the tracks.';

  Future<bool> _pay() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (_failNext) throw StateError('Card declined');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LATCH · FLUTTER',
                    style: TextStyle(color: Color(0xFF71717A), letterSpacing: 3.5, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirm with\nintent, not a tap.',
                    style: TextStyle(fontSize: 44, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -1.8),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'The thumb resists at first, clicks at the latch point, and only then runs the action. Early releases spring back. Keyboard and screen reader users confirm directly.',
                    style: TextStyle(color: _muted, fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 28),
                  _Card(
                    children: [
                      const Row(
                        children: [
                          Text('Order total', style: TextStyle(color: _muted)),
                          Spacer(),
                          Text('₹1,499', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('2 × Handloom cotton · Free delivery', style: TextStyle(color: _muted, fontSize: 13)),
                      const SizedBox(height: 20),
                      LatchSwipeConfirm(
                        key: ValueKey('pay-$_round'),
                        label: 'Swipe to pay ₹1,499',
                        doneLabel: 'Paid · order placed',
                        failedLabel: 'Card declined',
                        onConfirm: _pay,
                        onStateChanged: (s) => setState(() => _log = 'Payment: ${s.name}'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Switch(value: _failNext, onChanged: (v) => setState(() => _failNext = v)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Make the card decline', style: TextStyle(color: _muted)),
                          ),
                          TextButton(onPressed: () => setState(() => _round++), child: const Text('Reset')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Card(
                    children: [
                      const Text(
                        'Danger zone',
                        style: TextStyle(color: _danger, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Deleting removes your meals, streaks and account for good.',
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                      LatchSwipeConfirm(
                        label: 'Swipe to delete account',
                        doneLabel: 'Account deleted',
                        threshold: 0.94,
                        resetAfter: const Duration(seconds: 3),
                        thumbColor: _danger,
                        fillColor: const Color(0x33F87171),
                        doneColor: _danger,
                        onConfirm: () async {
                          await Future<void>.delayed(const Duration(milliseconds: 900));
                          return true;
                        },
                        onStateChanged: (s) => setState(() => _log = 'Delete: ${s.name}'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'This one needs 94% of the track and resets after three seconds.',
                        style: TextStyle(color: Color(0xFF71717A), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _line),
                    ),
                    child: Text(
                      _log,
                      style: const TextStyle(fontFamily: 'monospace', color: _muted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'MIT © 2026 Yagnik Barasiya · github.com/YagnikBarasiya23/latch_swipe_confirm',
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
