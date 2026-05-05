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
            InstructionOverlay.id: (ctx, g) => InstructionOverlay(game: g),
            StartOverlay.id: (ctx, g) => StartOverlay(game: g),
            GameOver.id: (ctx, g) => GameOver(game: g),
          },
          initialActiveOverlays: const [InstructionOverlay.id],
        ),
      ),
    );
  }
}

// --- การจัดการข้อมูล ---
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

// --- ตัวเกมหลัก ---
class CatchRehabGame extends FlameGame
    with HasCollisionDetection, KeyboardEvents {
  final Random _rng = Random();

  // 1. เปลี่ยนเป็น Basket? (Nullable) เพื่อให้ลบออกตอนหน้าเมนูได้
  Basket? basket;

  int _lastLaneIndex = -1;
  double timeLeft = 60; // ปรับเป็น 5 นาที (300 วินาที)
  int score = 0;
  int missed = 0;
  bool running = false;
  String selectedSpeed = 'กลาง';
  String selectedArmLevel = 'ง่าย';

  double ballSpeed = 0;
  double spawnEvery = 2.5;
  double _spawnAcc = 0;
  double currentDeg = 0;

  @override
  Color backgroundColor() => const Color.fromARGB(255, 200, 216, 227);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(ScreenHitbox());
    // ย้ายการสร้าง basket ไปไว้ใน setupAndStart เพื่อไม่ให้โผล่หน้าเมนู
  }

  void setupAndStart(String speed, String armLevel) {
    selectedSpeed = speed;
    selectedArmLevel = armLevel;
    score = 0;
    missed = 0;
    timeLeft = 60; // ตั้งค่าเวลาเล่นเป็น 5 นาที
    currentDeg = 0;
    _lastLaneIndex = -1;

    // 2. คำนวณความเร็วตามวินาทีที่คุณกำหนด (ระยะทาง / เวลา)
    double travelDistance = size.y + 100;

    if (speed.contains('ง่าย')) {
      ballSpeed = travelDistance / 25; // บอลจะใช้เวลา 25 วินาทีกว่าจะตกถึงพื้น
      spawnEvery = 15.0; // ปล่อยบอลทุกๆ 15 วินาที
    } else if (speed.contains('กลาง')) {
      ballSpeed = travelDistance / 15; // บอลจะใช้เวลา 15 วินาทีกว่าจะตกถึงพื้น
      spawnEvery = 10.0; // ปล่อยบอลทุกๆ 10 วินาที
    } else if (speed.contains('ยาก')) {
      ballSpeed = travelDistance / 10; // บอลจะใช้เวลา 10 วินาทีกว่าจะตกถึงพื้น
      spawnEvery = 7.0; // ปล่อยบอลทุกๆ 7 วินาที
    }

    _spawnAcc = spawnEvery;

    // 3. สร้างตะกร้าใหม่ทุกครั้งที่เริ่มเกม
    basket?.removeFromParent();
    basket = Basket(size: Vector2(120, 50))
      ..position = Vector2(size.x / 2 - 60, size.y - 120);
    add(basket!);

    running = true;
    overlays.remove(StartOverlay.id);
    overlays.add(Hud.id);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!running) return;
    timeLeft -= dt;

    if (timeLeft <= 0) {
      running = false;
      basket?.removeFromParent(); // ลบตะกร้าเมื่อจบเกม
      basket = null;
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

    // 4. ตรวจสอบ basket! (ใส่เครื่องหมาย !) เพื่อแก้เส้นสีแดง
    if (basket == null) return KeyEventResult.ignored;

    final lx = size.x * 0.2 - basket!.width / 2;
    final cx = size.x * 0.5 - basket!.width / 2;
    final rx = size.x * 0.8 - basket!.width / 2;

    bool canMove = false;
    if (selectedArmLevel.contains('ง่าย')) {
      if (currentDeg >= 0 && currentDeg <= 30) canMove = true;
    } else if (selectedArmLevel.contains('กลาง')) {
      if (currentDeg >= 30 && currentDeg <= 60) canMove = true;
    } else if (selectedArmLevel.contains('ยาก')) {
      if (currentDeg >= 60 && currentDeg <= 80) canMove = true;
    }

    if (canMove) {
      if (selectedArmLevel.contains('ง่าย')) {
        if (key == LogicalKeyboardKey.keyA) basket!.moveTo(lx, Colors.green);
        if (key == LogicalKeyboardKey.keyB) basket!.moveTo(cx, Colors.blue);
        if (key == LogicalKeyboardKey.keyC) basket!.moveTo(rx, Colors.red);
      } else if (selectedArmLevel.contains('กลาง')) {
        if (key == LogicalKeyboardKey.keyD) basket!.moveTo(lx, Colors.green);
        if (key == LogicalKeyboardKey.keyE) basket!.moveTo(cx, Colors.blue);
        if (key == LogicalKeyboardKey.keyF) basket!.moveTo(rx, Colors.red);
      } else if (selectedArmLevel.contains('ยาก')) {
        if (key == LogicalKeyboardKey.keyG) basket!.moveTo(lx, Colors.green);
        if (key == LogicalKeyboardKey.keyH) basket!.moveTo(cx, Colors.blue);
        if (key == LogicalKeyboardKey.keyI) basket!.moveTo(rx, Colors.red);
      }
    }
    return KeyEventResult.handled;
  }
}

// --- หน้า HUD ---
// --- หน้า HUD (ปรับตำแหน่งสถานะไว้ตรงกลางด้านบน) ---
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
            // 1. รับได้ และ พลาด (ฝั่งซ้ายบน)
            Positioned(
              top: 20,
              left: 20,
              child: Row(
                children: [
                  _statBox("รับได้", "${game.score}", Colors.green),
                  const SizedBox(width: 12),
                  _statBox("พลาด", "${game.missed}", Colors.red),
                ],
              ),
            ),

            // 2. เวลา (ฝั่งขวาบน)
            Positioned(
              top: 20,
              right: 20,
              child: _statBox(
                "เวลา",
                "${game.timeLeft.toInt()}s",
                Colors.orange,
              ),
            ),

            // 3. กรอบสถานะการยกแขน (ตรงกลางด้านบนสุด)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20), // ระยะห่างจากขอบบน
                child: Builder(
                  builder: (context) {
                    bool isReached = false;
                    // เช็คเงื่อนไขช่วงองศา
                    if (game.selectedArmLevel.contains('ง่าย')) {
                      if (game.currentDeg >= 0 && game.currentDeg <= 30)
                        isReached = true;
                    } else if (game.selectedArmLevel.contains('กลาง')) {
                      if (game.currentDeg >= 30 && game.currentDeg <= 60)
                        isReached = true;
                    } else if (game.selectedArmLevel.contains('ยาก')) {
                      if (game.currentDeg >= 60 && game.currentDeg <= 80)
                        isReached = true;
                    }

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 220, // ขยายให้กว้างขึ้น
                      padding: const EdgeInsets.symmetric(
                        vertical: 15,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: isReached ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (isReached ? Colors.green : Colors.red)
                                .withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        isReached ? "ยกถึงระดับ ✅" : "ยกไม่ถึงระดับ ❌",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22, // ปรับตัวอักษรให้ใหญ่ขึ้น
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 4. ปุ่มควบคุม (ซ้ายล่าง)
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  game.selectedArmLevel.contains('ง่าย')
                      ? 'ปุ่มควบคุม: A | B | C'
                      : (game.selectedArmLevel.contains('กลาง')
                            ? 'ปุ่มควบคุม: D | E | F'
                            : 'ปุ่มควบคุม: G | H | I'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ฟังก์ชันสร้างกรอบตัวเลข (รับได้/พลาด/เวลา)
  Widget _statBox(String label, String value, Color color) => Container(
    constraints: const BoxConstraints(minWidth: 90),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: color, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    ),
  );
}

// --- หน้าคำแนะนำ ---
class InstructionOverlay extends StatelessWidget {
  static const id = 'instruction';
  final CatchRehabGame game;
  const InstructionOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 25,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  "คำแนะนำการฝึก",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              _guideText(
                "ขั้นตอนที่ 1 : ",
                "เลือกความเร็วและระดับองศาการยกแขน ตามที่ต้องการฝึก",
              ),
              _guideText(
                "ขั้นตอนที่ 2 : ",
                "ควบคุมเกมโดยการขยับอุปกรณ์ไปวางบนสีตามตำแหน่งของลูก",
              ),
              _guideText(
                "ขั้นตอนที่ 3 : ",
                "รับลูกบอลให้ได้มากที่สุดในเวลา 5 นาที",
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  game.overlays.remove(id);
                  game.overlays.add(StartOverlay.id);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  "เข้าสู่หน้าเลือกระดับ",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideText(String t, String d) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          t,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color.fromARGB(255, 8, 23, 109),
          ),
        ),
        Text(
          d,
          style: const TextStyle(
            fontSize: 18,
            color: Color.fromARGB(255, 8, 23, 109),
          ),
        ),
      ],
    ),
  );
}

// --- หน้าเลือกระดับ ---
class StartOverlay extends StatefulWidget {
  static const id = 'start';
  final CatchRehabGame game;
  const StartOverlay({super.key, required this.game});
  @override
  State<StartOverlay> createState() => _StartOverlayState();
}

class _StartOverlayState extends State<StartOverlay> {
  String s = 'กลาง (15 วินาที)';
  String a = 'ง่าย (0-30 องศา)';
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "เริ่มการฝึก",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _chipGroup(
                "เลือกความเร็วลูกบอล",
                ['ง่าย (25 วินาที)', 'กลาง (15 วินาที)', 'ยาก (10 วินาที)'],
                s,
                (v) => setState(() => s = v),
              ),
              _chipGroup(
                "เลือกระดับการยกแขน",
                ['ง่าย (0-30 องศา)', 'กลาง (30-60 องศา)', 'ยาก (60 องศา)'],
                a,
                (v) => setState(() => a = v),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => widget.game.setupAndStart(s, a),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text("เริ่มเกม"),
              ),

              TextButton(
                onPressed: () {
                  widget.game.overlays.remove(StartOverlay.id);
                  widget.game.overlays.add(InstructionOverlay.id);
                },
                child: const Text(
                  "ย้อนกลับไปหน้าวิธีเล่น",
                  style: TextStyle(fontSize: 18),
                ),
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
      Text(
        t,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black54,
        ),
      ),
      const SizedBox(height: 15),
      Wrap(
        spacing: 15, // เพิ่มระยะห่างระหว่างปุ่ม
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: opts
            .map(
              (o) => ChoiceChip(
                label: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ), // เพิ่มพื้นที่ในปุ่ม
                  child: Text(o),
                ),
                labelStyle: TextStyle(
                  fontSize: 18, // ขยายตัวอักษรในปุ่ม ChoiceChip
                  fontWeight: FontWeight.bold,
                  color: cur == o ? Colors.white : Colors.black87,
                ),
                selected: cur == o,
                selectedColor: Colors.indigo,
                backgroundColor: Colors.grey[200],
                onSelected: (_) => onS(o),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 25),
    ],
  );
}

// --- ตะกร้า ---
class Basket extends PositionComponent with CollisionCallbacks {
  late Paint _basketPaint;
  Basket({required Vector2 size}) : super(size: size, anchor: Anchor.topLeft) {
    _basketPaint = Paint()..color = const Color.fromARGB(255, 172, 91, 3);
  }
  void moveTo(double nx, Color c) {
    x = nx;
    _basketPaint.color = c;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        bottomLeft: const Radius.circular(15),
        bottomRight: const Radius.circular(15),
      ),
      _basketPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-5, -5, size.x + 10, 10),
        const Radius.circular(5),
      ),
      Paint()..color = _basketPaint.color.withOpacity(0.8),
    );
  }
}

// --- ลูกบอล ---
class Ball extends CircleComponent
    with CollisionCallbacks, HasGameReference<CatchRehabGame> {
  Ball({required Vector2 start})
    : super(
        radius: 25,
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
    position.y += game.ballSpeed * dt;
    if (y > game.size.y + 100) {
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

// --- หน้าจบเกม (จุดที่มีการแก้ไข) ---
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
                  _resBox("รับได้", "${game.score}", Colors.green),
                  const SizedBox(width: 20),
                  _resBox("พลาด", "${game.missed}", Colors.red),
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
                  label: const Text("บันทึกผล"),
                ),

              // แก้ไขปุ่มกลับหน้าหลัก
              TextButton(
                onPressed: () {
                  sheet.resetStatus();
                  game.overlays.remove(
                    GameOver.id,
                  ); // บรรทัดสำคัญ: ลบหน้าจอนี้ออกก่อน
                  game.overlays.add(
                    InstructionOverlay.id,
                  ); // แล้วค่อยกลับไปหน้าอธิบาย
                },
                child: const Text("กลับหน้าหลัก"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resBox(String l, String v, Color c) => Column(
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
