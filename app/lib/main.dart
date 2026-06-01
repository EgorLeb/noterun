import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/auth_screen.dart';
import 'screens/menu_screen.dart';
import 'services/api_service.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const NoteRunApp());
}

class NoteRunApp extends StatelessWidget {
  const NoteRunApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteRun',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111318),
      ),
      home: const _StartupRouter(),
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
    );
  }
}

class _StartupRouter extends StatefulWidget {
  const _StartupRouter();
  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final loggedIn = await ApiService.isLoggedIn();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => loggedIn ? const MenuScreen() : const AuthScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD740))),
    );
  }
}
