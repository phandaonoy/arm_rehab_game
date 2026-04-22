import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyEvent, KeyDownEvent, LogicalKeyboardKey;

void main() {
  final game = CatchRehabGame();
  runApp(
    GameWidget(
      game: game,
      overlayBuilderMap: {
        Hud.id: (ctx, g) => Hud(game: g as CatchRehabGame),
        StartOverlay.id: (ctx, g) => StartOverlay(game: g as CatchRehabGame),
        GameOver.id: (ctx, g) => GameOver(game: g as CatchRehabGame),
      },
      // ต้องเป็น "List<String>" ไม่ใช่ Set → ใช้ [] แทน {}
      initialActiveOverlays: const [StartOverlay.id],
    ),
  );
}

/// ---------------- Core Game ----------------
class CatchRehabGame extends FlameGame
    with HasCollisionDetection, KeyboardEvents, PanDetector {
  final Random _rng = Random();

  late Basket basket;
  late ArrowArm arm;

  double timeLeft = 30; // วินาที
  int score = 0;
  int missed = 0;
  bool running = false;

  double gravity = 900; // px/s^2
  double spawnEvery = 1.0; // วินาที/ลูก
  double _spawnAcc = 0;

  @override
  Color backgroundColor() => const Color(0xFFE8F5E9); // เขียวอ่อน

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(ScreenHitbox());

    // พื้น (อ้างอิงสายตา)
    add(
      RectangleComponent(
        position: Vector2(0, size.y - 24),
        size: Vector2(size.x, 24),
        paint: Paint()..color = const Color(0x22000000),
      ),
    );

    basket = Basket(size: Vector2(110, 22))
      ..position = Vector2(size.x / 2, size.y - 35);
    add(basket);

    arm = ArrowArm()..position = Vector2(60, size.y - 60); // โคนแขน
    add(arm);
  }

  void startRound() {
    score = 0;
    missed = 0;
    timeLeft = 30;
    running = true;
    overlays.remove(StartOverlay.id);
    overlays.remove(GameOver.id);
    overlays.add(Hud.id);
  }

  void stopRound() {
    running = false;
    overlays.remove(Hud.id);
    overlays.add(GameOver.id);
  }

  void addPoint() => score++;
  void addMiss() => missed++;

  void spawnBall() {
    final x = 20 + _rng.nextDouble() * (size.x - 40);
    final ball = Ball(
      start: Vector2(x, -16),
      gravity: gravity,
      color: const Color(0xFF42A5F5),
    );
    add(ball);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!running) return;

    // เวลา
    timeLeft -= dt;
    if (timeLeft <= 0) {
      timeLeft = 0;
      stopRound();
      return;
    }

    // ปล่อยบอลเป็นช่วง ๆ
    _spawnAcc += dt;
    if (_spawnAcc >= spawnEvery) {
      _spawnAcc = 0;
      spawnBall();
      // เพิ่มความยากทีละนิด
      spawnEvery = (spawnEvery * 0.985).clamp(0.45, 2.0);
    }
  }

  /// เมาส์/นิ้วลาก = ย้ายตะกร้าแกน X
  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (!running) return;
    basket.x = (basket.x + info.delta.global.x).clamp(0, size.x - basket.width);
  }

  /// คีย์บอร์ด: ←/→ ย้ายตะกร้า, ↑/↓ หมุนลูกศร (แขน)
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (!running) return KeyEventResult.ignored;

    const moveSpeed = 360.0; // px/คีย์ดาวน์หนึ่งครั้ง (ประมาณเฟรม 60Hz)
    if (event is KeyDownEvent) {
      if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
        basket.x = (basket.x - moveSpeed * 0.016).clamp(
          0,
          size.x - basket.width,
        );
        return KeyEventResult.handled;
      }
      if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
        basket.x = (basket.x + moveSpeed * 0.016).clamp(
          0,
          size.x - basket.width,
        );
        return KeyEventResult.handled;
      }
      if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
        arm.setAngleDegrees((arm.deg - 4).clamp(-60, 60));
        return KeyEventResult.handled;
      }
      if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
        arm.setAngleDegrees((arm.deg + 4).clamp(-60, 60));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

/// --------------- Basket (ตะกร้า) ---------------
class Basket extends RectangleComponent with CollisionCallbacks {
  Basket({required Vector2 size})
    : super(
        size: size,
        anchor: Anchor.topLeft,
        paint: Paint()..color = const Color(0xFF6D4C41), // น้ำตาล
      );

  @override
  double get width => size.x;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }
}

/// --------------- Ball (ลูกบอล) ---------------
class Ball extends CircleComponent
        // ใช้ HasGameReference แล้วพร็อพชื่อ "game" (ไม่ใช่ gameRef)
        with
        CollisionCallbacks,
        HasGameReference<CatchRehabGame> {
  Ball({required Vector2 start, required this.gravity, required Color color})
    : super(
        position: start,
        radius: 14,
        anchor: Anchor.center,
        paint: Paint()..color = color,
      );

  final double gravity;
  Vector2 vel = Vector2(0, 0);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    vel.y += gravity * dt;
    position += vel * dt;

    // พ้นจอ = พลาด
    if (y > game.size.y + 30) {
      game.addMiss();
      removeFromParent();
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is Basket) {
      game.addPoint();
      removeFromParent();
    }
  }
}

/// --------------- ArrowArm (ลูกศรแทนแขน) ---------------
class ArrowArm extends PositionComponent {
  double deg = 0; // องศาปัจจุบัน

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFEF5350); // แดง

    // ความยาวแขน
    const len = 120.0;
    final rad = deg * pi / 180;
    final start = Offset(x, y);
    final end = Offset(x + len * cos(rad), y + len * sin(rad));

    // วาดก้าน
    final linePaint = Paint()
      ..strokeWidth = 6
      ..color = const Color(0xFFEF5350);
    canvas.drawLine(start, end, linePaint);

    // หัวลูกศร
    const arrowSize = 12.0;
    final left = Offset(
      end.dx - arrowSize * cos(rad - pi / 6),
      end.dy - arrowSize * sin(rad - pi / 6),
    );
    final right = Offset(
      end.dx - arrowSize * cos(rad + pi / 6),
      end.dy - arrowSize * sin(rad + pi / 6),
    );
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, paint);

    // ป้ายองศา
    final tp = TextPainter(
      text: TextSpan(
        text: '${deg.toStringAsFixed(0)}°',
        style: const TextStyle(fontSize: 12, color: Colors.black),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x + 6, y - 22));
  }

  void setAngleDegrees(double d) => deg = d;
}

/// --------------- HUD / Overlays ---------------
class Hud extends StatelessWidget {
  static const id = 'hud';
  final CatchRehabGame game;
  const Hud({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chip('คะแนน', '${game.score}'),
              _chip('พลาด', '${game.missed}'),
              _chip('เวลา', '${game.timeLeft.toStringAsFixed(1)} s'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class StartOverlay extends StatelessWidget {
  static const id = 'start';
  final CatchRehabGame game;
  const StartOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return _centerCard(
      title: 'เกมรับลูกบอล',
      subtitle:
          'บังคับตะกร้าด้วย ← → หรือเมาส์ลาก\nหมุน “แขน (ลูกศร)” ด้วย ↑ ↓\nเก็บคะแนนให้ได้มากสุดใน 30 วินาที',
      buttonText: 'เริ่มเล่น',
      onPressed: game.startRound,
    );
  }
}

class GameOver extends StatelessWidget {
  static const id = 'over';
  final CatchRehabGame game;
  const GameOver({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return _centerCard(
      title: 'หมดเวลา!',
      subtitle: 'คะแนน: ${game.score}   พลาด: ${game.missed}',
      buttonText: 'เล่นอีกครั้ง',
      onPressed: game.startRound,
    );
  }
}

Widget _centerCard({
  required String title,
  required String subtitle,
  required String buttonText,
  required VoidCallback onPressed,
}) {
  return ColoredBox(
    color: const Color(0xAA000000),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          elevation: 6,
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton(onPressed: onPressed, child: Text(buttonText)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
