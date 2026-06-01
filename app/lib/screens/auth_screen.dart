import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'menu_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin   = true;
  bool _loading   = false;
  String _error   = '';

  final _email    = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose(); _username.dispose(); _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = ''; });
    try {
      if (_isLogin) {
        await ApiService.login(_email.text.trim(), _password.text);
      } else {
        if (_username.text.trim().isEmpty) {
          setState(() { _error = 'Введи имя пользователя'; _loading = false; });
          return;
        }
        await ApiService.register(
            _email.text.trim(), _username.text.trim(), _password.text);
      }
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const MenuScreen()));
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Нет связи с сервером'; _loading = false; });
    }
  }

  void _skipLogin() {
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const MenuScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('NoteRun',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD740))),
              const SizedBox(height: 8),
              Text(_isLogin ? 'Вход' : 'Регистрация',
                  style: const TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 32),

              _Field(controller: _email,    label: 'Email',    icon: Icons.email_outlined,
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: 12),

              if (!_isLogin) ...[
                _Field(controller: _username, label: 'Имя пользователя', icon: Icons.person_outline),
                const SizedBox(height: 12),
              ],

              _Field(controller: _password,  label: 'Пароль', icon: Icons.lock_outline,
                  obscure: true),
              const SizedBox(height: 8),

              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error,
                      style: const TextStyle(color: Color(0xFFF44336), fontSize: 13)),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD740),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : Text(_isLogin ? 'Войти' : 'Зарегистрироваться',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _isLogin = !_isLogin; _error = '';
                }),
                child: Text(_isLogin
                    ? 'Нет аккаунта? Зарегистрироваться'
                    : 'Уже есть аккаунт? Войти',
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
              ),

              const SizedBox(height: 4),
              TextButton(
                onPressed: _skipLogin,
                child: const Text('Играть без аккаунта',
                    style: TextStyle(color: Color(0xFF555566), fontSize: 12)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboard;
  const _Field({required this.controller, required this.label,
      required this.icon, this.obscure = false, this.keyboard});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText:    label,
        labelStyle:   const TextStyle(color: Color(0xFF888888)),
        prefixIcon:   Icon(icon, color: const Color(0xFF888888)),
        filled:       true,
        fillColor:    const Color(0xFF1E2030),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFFD740), width: 1.5),
        ),
      ),
    );
  }
}
