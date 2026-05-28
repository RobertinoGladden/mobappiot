import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
	final bool isLoggedIn;
	final Widget loggedInDestination;
	final Widget loggedOutDestination;

	const SplashScreen({
		super.key,
		required this.isLoggedIn,
		required this.loggedInDestination,
		required this.loggedOutDestination,
	});

	@override
	State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
		with SingleTickerProviderStateMixin {
	late final AnimationController _animationController;

	@override
	void initState() {
		super.initState();
		_animationController = AnimationController(
			vsync: this,
			duration: const Duration(seconds: 6),
		)..repeat(reverse: true);

		_startBootstrap();
	}

	Future<void> _startBootstrap() async {
		await Future<void>.delayed(const Duration(milliseconds: 1400));

		if (!mounted) {
			return;
		}

		Navigator.of(context).pushReplacement(
			MaterialPageRoute(
				builder: (_) => widget.isLoggedIn
						? widget.loggedInDestination
						: widget.loggedOutDestination,
			),
		);
	}

	@override
	void dispose() {
		_animationController.dispose();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			body: AnimatedBuilder(
				animation: _animationController,
				builder: (context, child) {
					final animationValue = _animationController.value;
					final pulse = Curves.easeInOut.transform(_animationController.value);
					return Container(
						decoration: const BoxDecoration(
							gradient: LinearGradient(
								begin: Alignment.topCenter,
								end: Alignment.bottomCenter,
								colors: [
									Color(0xFF2D63EA),
									Color(0xFF2F7BEF),
									Color(0xFF38A5F1),
								],
							),
						),
						child: Stack(
							children: [
								..._buildFloatingBubbles(pulse),
								Positioned.fill(
									child: CustomPaint(
										painter: _SplashWavePainter(
											animationValue: animationValue,
										),
									),
								),
								SafeArea(
									child: Center(
										child: Padding(
											padding: const EdgeInsets.symmetric(horizontal: 24),
											child: Column(
												mainAxisAlignment: MainAxisAlignment.center,
												children: [
													const Spacer(flex: 2),
													_buildLogo(pulse),
													const SizedBox(height: 18),
													const Text(
														'BluVera',
														textAlign: TextAlign.center,
														style: TextStyle(
															color: Colors.white,
															fontSize: 36,
															fontWeight: FontWeight.w800,
															letterSpacing: 0.2,
														),
													),
													const SizedBox(height: 8),
													Container(
														width: 92,
														height: 2,
														decoration: BoxDecoration(
															gradient: LinearGradient(
																colors: [
																	Colors.white.withOpacity(0.15),
																	Colors.white,
																	Colors.white.withOpacity(0.15),
																],
															),
														),
													),
													const SizedBox(height: 8),
													const Text(
														'Smart IoT monitoring system',
														textAlign: TextAlign.center,
														style: TextStyle(
															color: Colors.white,
															fontSize: 16,
															fontWeight: FontWeight.w600,
														),
													),
													const SizedBox(height: 14),
													_buildLoadingIndicator(animationValue),
													const SizedBox(height: 14),
													const Spacer(flex: 1),
													const Column(
														children: [
															Text(
																'Memuat Sistem',
																style: TextStyle(
																	color: Color(0xFF2563EB),
																	fontSize: 13,
																	fontWeight: FontWeight.w700,
																),
															),
															Text(
																'Versi 1.0',
																style: TextStyle(
																	color: Color(0xFF2563EB),
																	fontSize: 11,
																	fontWeight: FontWeight.w600,
																),
															),
														],
													),
													const SizedBox(height: 28),
												],
											),
										),
									),
								),
							],
						),
					);
				},
			),
		);
	}

	Widget _buildLogo(double pulse) {
		final scale = 1 + (pulse * 0.02);

		return Transform.scale(
			scale: scale,
			child: SizedBox(
				width: 132,
				height: 132,
				child: Image.asset(
					'assets/icons/LOGO TA (ikon puth).png',
					fit: BoxFit.contain,
				),
			),
		);
	}

	Widget _buildLoadingIndicator(double animationValue) {
		final phase = animationValue * math.pi * 2;
		final progress = 0.35 + (math.sin(phase) + 1) * 0.16;
		final dotOne = 0.45 + (math.sin(phase) + 1) * 0.25;
		final dotTwo = 0.45 + (math.sin(phase + 2.1) + 1) * 0.25;
		final dotThree = 0.45 + (math.sin(phase + 4.2) + 1) * 0.25;

		return Column(
			mainAxisSize: MainAxisSize.min,
			children: [
				ClipRRect(
					borderRadius: BorderRadius.circular(999),
					child: Container(
						width: 168,
						height: 6,
						decoration: BoxDecoration(
							color: Colors.white.withOpacity(0.18),
						),
						child: Align(
							alignment: Alignment.centerLeft,
							child: FractionallySizedBox(
								widthFactor: progress,
								child: Container(
									decoration: BoxDecoration(
										gradient: LinearGradient(
											begin: Alignment.centerLeft,
											end: Alignment.centerRight,
											colors: [
												Colors.white.withOpacity(0.35),
												Colors.white,
												Colors.white.withOpacity(0.35),
											],
										),
									),
								),
							),
						),
					),
				),
				const SizedBox(height: 8),
				Row(
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
						_AnimatedDot(opacity: dotOne),
						const SizedBox(width: 6),
						_AnimatedDot(opacity: dotTwo),
						const SizedBox(width: 6),
						_AnimatedDot(opacity: dotThree),
					],
				),
			],
		);
	}

	List<Widget> _buildFloatingBubbles(double pulse) {
		final bubbleOpacity = 0.08 + (pulse * 0.06);

		return [
			_Bubble(top: 36, left: 34, size: 48, opacity: bubbleOpacity),
			_Bubble(top: 132, right: 42, size: 20, opacity: bubbleOpacity * 0.9),
			_Bubble(top: 220, right: 74, size: 14, opacity: bubbleOpacity * 0.8),
			_Bubble(top: 284, left: 56, size: 18, opacity: bubbleOpacity * 0.85),
			_Bubble(bottom: 128, left: 38, size: 56, opacity: bubbleOpacity * 0.9),
			_Bubble(bottom: 96, right: 38, size: 30, opacity: bubbleOpacity * 0.8),
		];
	}
}

class _AnimatedDot extends StatelessWidget {
	final double opacity;

	const _AnimatedDot({required this.opacity});

	@override
	Widget build(BuildContext context) {
		return Container(
			width: 8,
			height: 8,
			decoration: BoxDecoration(
				shape: BoxShape.circle,
				color: Colors.white.withOpacity(opacity),
			),
		);
	}
}

class _Bubble extends StatelessWidget {
	final double? top;
	final double? left;
	final double? right;
	final double? bottom;
	final double size;
	final double opacity;

	const _Bubble({
		this.top,
		this.left,
		this.right,
		this.bottom,
		required this.size,
		required this.opacity,
	});

	@override
	Widget build(BuildContext context) {
		return Positioned(
			top: top,
			left: left,
			right: right,
			bottom: bottom,
			child: Container(
				width: size,
				height: size,
				decoration: BoxDecoration(
					shape: BoxShape.circle,
					color: Colors.white.withOpacity(opacity),
				),
			),
		);
	}
}

class _SplashWavePainter extends CustomPainter {
	final double animationValue;

	const _SplashWavePainter({required this.animationValue});

	@override
	void paint(Canvas canvas, Size size) {
		final baseY = size.height * 0.70;
		final phase = animationValue * math.pi * 2;
		final waveOffset = 10 + (math.sin(phase) + 1) * 9;

		_drawWave(
			canvas,
			size,
			baseY,
			Colors.white.withOpacity(0.22),
			waveOffset * 0.0,
			phase,
			0.0,
		);
		_drawWave(
			canvas,
			size,
			baseY + 36,
			Colors.white.withOpacity(0.28),
			waveOffset * 0.55,
			phase,
			1.1,
		);
		_drawWave(
			canvas,
			size,
			baseY + 72,
			Colors.white.withOpacity(0.22),
			waveOffset * 1.0,
			phase,
			2.2,
		);
		_drawWave(
			canvas,
			size,
			baseY + 108,
			Colors.white.withOpacity(0.16),
			waveOffset * 1.35,
			phase,
			3.3,
		);
	}

	void _drawWave(
		Canvas canvas,
		Size size,
		double startY,
		Color color,
		double amplitude,
		double phase,
		double phaseOffset,
	) {
		final paint = Paint()..color = color;
		final path = Path();
		final motion = math.sin(phase + phaseOffset) * 8;
		final waveHeight = amplitude + (math.sin(phase * 1.3 + phaseOffset) * 2.5);
		final y = startY + motion;

		path.moveTo(0, size.height);
		path.lineTo(0, y);

		final width = size.width;
		path.cubicTo(
			width * 0.15,
			y - waveHeight,
			width * 0.28,
			y + waveHeight,
			width * 0.42,
			y + waveHeight * 0.1,
		);
		path.cubicTo(
			width * 0.56,
			y - waveHeight * 0.85,
			width * 0.68,
			y + waveHeight * 0.95,
			width * 0.83,
			y + waveHeight * 0.15,
		);
		path.cubicTo(
			width * 0.92,
			y - waveHeight * 0.55,
			width * 0.98,
			y + waveHeight * 0.35,
			width,
			y + waveHeight * 0.1,
		);
		path.lineTo(width, size.height);
		path.close();

		canvas.drawPath(path, paint);
	}

	@override
	bool shouldRepaint(covariant _SplashWavePainter oldDelegate) {
		return oldDelegate.animationValue != animationValue;
	}
}
