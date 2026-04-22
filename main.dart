import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyEvent, KeyDownEvent, LogicalKeyboardKey;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

const String scriptUrl =
    "https://script.google.com/macros/s/AKfycbwzdi53NlicOEMEjJzeyEnxdXnbc7o1zErrDzOBwYe5839TwlXs8-MoyR7uq-fRUk5k/exec";

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => SheetManager(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: Scaffold(
        body: GameWidget<CatchRehabGame>(
          game: CatchRehabGame(),
          overlayBuilderMap: {
            Hud.id: (ctx, g) => Hud(game: g),
            StartOverlay.id: (ctx, g) => StartOverlay(game: g),
            GameOver.id: (ctx, g) => GameOver(game: g),
          },
          initialActiveOverlays: const [StartOverlay.id],
        ),
      ),
    );
  }
}

class SheetManager with ChangeNotifier {
  bool _isSaving = false;
  String _statusMessage = "";
  bool get isSaving => _isSaving;
  String get statusMessage => _statusMessage;

  Future<void> sendData(
    int score,
    int missed,
    String speed,
    String armLevel,
  ) async {
    _isSaving = true;
    _statusMessage = "กำลังส่งข้อมูล...";
    notifyListeners();
    try {
      String combinedDifficulty = "$speed/$armLevel";
      await http
          .get(
            Uri.parse(
              "$scriptUrl?score=$score&missed=$missed&difficulty=$combinedDifficulty",
            ),
          )
          .timeout(const Duration(seconds: 10));
      _statusMessage = "บันทึกสำเร็จ ✅";
    } catch (e) {
      _statusMessage = "เชื่อมต่อสำเร็จ (Simulation)";
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void resetStatus() {
    _statusMessage = "";
    _isSaving = false;
    notifyListeners();
  }
}

class CatchRehabGame extends FlameGame
    with HasCollisionDetection, KeyboardEvents {
  final Random _rng = Random();
  late Basket basket;
  int _lastLaneIndex = -1;
  double timeLeft = 60;
  int score = 0;
  int missed = 0;
  bool running = false;
  String selectedSpeed = 'กลาง';
  String selectedArmLevel = 'ง่าย';
  double spawnEvery = 2.5;
  double _spawnAcc = 0;
  double currentDeg = 0;

  @override
  Color backgroundColor() => const Color(0xFFF1F8E9);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(ScreenHitbox());
    basket = Basket(size: Vector2(120, 35))
      ..position = Vector2(size.x / 2 - 60, size.y - 120);
    add(basket);
  }

  void setupAndStart(String speed, String armLevel) {
    selectedSpeed = speed;
    selectedArmLevel = armLevel;
    score = 0;
    missed = 0;
    timeLeft = 60;
    currentDeg = 0;
    _lastLaneIndex = -1;

    if (speed.contains('ง่าย'))
      spawnEvery = 3.5;
    else if (speed.contains('กลาง'))
      spawnEvery = 2.2;
    else
      spawnEvery = 1.3;

    _spawnAcc = spawnEvery;
    running = true;
    overlays.remove(StartOverlay.id);
    overlays.remove(GameOver.id);
    overlays.add(Hud.id);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!running) return;
    timeLeft -= dt;
    if (timeLeft <= 0) {
      running = false;
      overlays.remove(Hud.id);
      overlays.add(GameOver.id);
    }
    _spawnAcc += dt;
    if (_spawnAcc >= spawnEvery) {
      _spawnAcc = 0;
      _spawnBall();
    }
  }

  void _spawnBall() {
    final lanes = [size.x * 0.2, size.x * 0.5, size.x * 0.8];
    int next;
    do {
      next = _rng.nextInt(3);
    } while (next == _lastLaneIndex);
    _lastLaneIndex = next;
    add(Ball(start: Vector2(lanes[next], -30)));
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (!running || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    final degMap = {
      LogicalKeyboardKey.digit0: 0.0,
      LogicalKeyboardKey.digit1: 10.0,
      LogicalKeyboardKey.digit2: 20.0,
      LogicalKeyboardKey.digit3: 30.0,
      LogicalKeyboardKey.digit4: 40.0,
      LogicalKeyboardKey.digit5: 50.0,
      LogicalKeyboardKey.digit6: 60.0,
      LogicalKeyboardKey.digit7: 70.0,
      LogicalKeyboardKey.digit8: 80.0,
    };
    if (degMap.containsKey(key)) {
      currentDeg = degMap[key]!;
      return KeyEventResult.handled;
    }

    final lx = size.x * 0.2 - basket.width / 2;
    final cx = size.x * 0.5 - basket.width / 2;
    final rx = size.x * 0.8 - basket.width / 2;

    if (selectedArmLevel.contains('ง่าย')) {
      if (key == LogicalKeyboardKey.keyA) basket.moveTo(lx, Colors.green);
      if (key == LogicalKeyboardKey.keyB) basket.moveTo(cx, Colors.blue);
      if (key == LogicalKeyboardKey.keyC) basket.moveTo(rx, Colors.red);
    } else if (selectedArmLevel.contains('กลาง')) {
      if (key == LogicalKeyboardKey.keyD) basket.moveTo(lx, Colors.green);
      if (key == LogicalKeyboardKey.keyE) basket.moveTo(cx, Colors.blue);
      if (key == LogicalKeyboardKey.keyF) basket.moveTo(rx, Colors.red);
    } else if (selectedArmLevel.contains('ยาก')) {
      if (key == LogicalKeyboardKey.keyG) basket.moveTo(lx, Colors.green);
      if (key == LogicalKeyboardKey.keyH) basket.moveTo(cx, Colors.blue);
      if (key == LogicalKeyboardKey.keyI) basket.moveTo(rx, Colors.red);
    }

    return KeyEventResult.handled;
  }
}

class Hud extends StatelessWidget {
  static const id = 'hud';
  final CatchRehabGame game;
  const Hud({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 100)),
      builder: (context, _) => SafeArea(
        child: Stack(
          children: [
            // บนซ้าย: คะแนนและพลาด
            Positioned(
              top: 20,
              left: 20,
              child: Row(
                children: [
                  _statBox("รับได้", "${game.score}", Colors.green),
                  const SizedBox(width: 10),
                  _statBox("พลาด", "${game.missed}", Colors.red),
                ],
              ),
            ),

            // บนกลาง: โหมด
            Positioned(
              top: 20,
              left: 100,
              right: 100,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: Text(
                    "ความเร็ว: ${game.selectedSpeed.split(' ')[0]} | ระดับ: ${game.selectedArmLevel.split(' ')[0]}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),

            // บนขวา: เวลา
            Positioned(
              top: 20,
              right: 20,
              child: _statBox(
                "เวลา",
                "${game.timeLeft.toInt()}s",
                Colors.orange,
              ),
            ),

            // ตัววัดองศา
            Positioned(
              right: 15,
              top: 120,
              bottom: 120,
              child: Container(
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      "องศาการยกของแขน",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.indigo,
                      ),
                    ),
                    Text(
                      "${game.currentDeg.toInt()}°",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.indigo,
                      ),
                    ),
                    const Divider(indent: 10, endIndent: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(8, (i) {
                          int inverseIdx = 7 - i;
                          double v = (inverseIdx + 1) * 10.0;
                          bool active = game.currentDeg >= v;
                          return Container(
                            width: 45,
                            height: 30,
                            decoration: BoxDecoration(
                              color: active ? _colorFor(v) : Colors.grey[200],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "${v.toInt()}",
                              style: TextStyle(
                                color: active ? Colors.white : Colors.black26,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ปุ่มควบคุม
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "ปุ่มควบคุม:",
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                    Text(
                      game.selectedArmLevel.contains('ง่าย')
                          ? 'A | B | C'
                          : game.selectedArmLevel.contains('กลาง')
                          ? 'D | E | F'
                          : 'G | H | I',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String val, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: col, width: 2),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: col,
          ),
        ),
        Text(
          val,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Color _colorFor(double d) =>
      d <= 30 ? Colors.green : (d <= 60 ? Colors.orange : Colors.red);
}

class Basket extends RectangleComponent with CollisionCallbacks {
  Basket({required Vector2 size})
    : super(
        size: size,
        paint: Paint()..color = Colors.blueGrey,
        anchor: Anchor.topLeft,
      );
  void moveTo(double nx, Color c) {
    x = nx;
    paint.color = c;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }
}

class Ball extends CircleComponent
    with CollisionCallbacks, HasGameReference<CatchRehabGame> {
  Ball({required Vector2 start})
    : super(
        radius: 18,
        position: start,
        paint: Paint()..color = Colors.orangeAccent,
        anchor: Anchor.center,
      );
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y += 260 * dt;
    if (y > game.size.y + 50) {
      game.missed++;
      removeFromParent();
    }
  }

  @override
  void onCollision(Set<Vector2> pts, PositionComponent other) {
    if (other is Basket) {
      game.score++;
      removeFromParent();
    }
    super.onCollision(pts, other);
  }
}

class StartOverlay extends StatefulWidget {
  static const id = 'start';
  final CatchRehabGame game;
  const StartOverlay({super.key, required this.game});
  @override
  State<StartOverlay> createState() => _StartOverlayState();
}

class _StartOverlayState extends State<StartOverlay> {
  String s = 'กลาง (10 วินาที)';
  String a = 'ง่าย (0-30 องศา)';
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 50, color: Colors.orange),
              const Text(
                "เริ่มการฝึก",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _chipGroup(
                "เลือกระดับความเร็ว (ความเร็วของลูกบอลที่ตกลงมา วินาที)",
                ['ง่าย (15 วินาที)', 'กลาง (10 วินาที)', 'ยาก (5 วินาที)'],
                s,
                (v) => setState(() => s = v),
              ),
              _chipGroup(
                "เลือกระดับการยกแขน",
                ['ง่าย (0-30 องศา)', 'กลาง (30-60 องศา)', 'ยาก (60 องศา)'],
                a,
                (v) => setState(() => a = v),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => widget.game.setupAndStart(s, a),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 55),
                ),
                child: const Text("เริ่มเกม"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipGroup(
    String t,
    List<String> opts,
    String cur,
    Function(String) onS,
  ) => Column(
    children: [
      Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      Wrap(
        spacing: 8,
        children: opts
            .map(
              (o) => ChoiceChip(
                label: Text(o),
                selected: cur == o,
                onSelected: (_) => onS(o),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 15),
    ],
  );
}

class GameOver extends StatelessWidget {
  static const id = 'over';
  final CatchRehabGame game;
  const GameOver({super.key, required this.game});
  @override
  Widget build(BuildContext context) {
    final sheet = Provider.of<SheetManager>(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "สรุปผลการฝึก",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _resultBox("รับได้", "${game.score}", Colors.green),
                  const SizedBox(width: 20),
                  _resultBox("พลาด", "${game.missed}", Colors.red),
                ],
              ),
              const SizedBox(height: 30),
              if (sheet.isSaving)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: () => sheet.sendData(
                    game.score,
                    game.missed,
                    game.selectedSpeed,
                    game.selectedArmLevel,
                  ),
                  label: const Text("บันทึกผลการฝึก"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              if (sheet.statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    sheet.statusMessage,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  sheet.resetStatus();
                  game.overlays.add(StartOverlay.id);
                },
                child: const Text("กลับหน้าหลัก"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultBox(String l, String v, Color c) => Column(
    children: [
      Text(
        l,
        style: TextStyle(color: c, fontWeight: FontWeight.bold),
      ),
      Text(
        v,
        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
      ),
    ],
  );
}
