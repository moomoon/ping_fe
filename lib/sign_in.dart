import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:ping_fe/api.dart';
import 'package:ping_fe/main_router.dart';
import 'package:ping_fe/account.dart';

class SignIn extends StatefulWidget {
  const SignIn({Key key}) : super(key: key);
  @override
  State<StatefulWidget> createState() {
    return SignInState();
  }
}

class LoginPwd {
  String name = '';
  String password = '';
}

class SignInState extends State<SignIn> {
  LoginPwd account = LoginPwd();

  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormFieldState<String>> _passwordFieldKey =
      GlobalKey<FormFieldState<String>>();

  void showInSnackBar(String value) {
    Scaffold.of(context).showSnackBar(SnackBar(
      content: Text(value),
    ));
  }

  void _handleSubmitted() async {
    final FormState form = _formKey.currentState;
    if (!form.validate()) {
      _autovalidateMode = AutovalidateMode
          .onUserInteraction; // Start validating on every change.
      showInSnackBar('Please fix the errors in red before submitting.');
    } else {
      form.save();
      final resp = await context.api
          .signInWithPwd(username: account.name, password: account.password);
      context.accountStore.value =
          Account(token: resp.token, username: resp.username);
    }
  }

  String _validateName(String value) {
    if (value?.trim()?.isNotEmpty != true) return 'email';
    return null;
  }

  Widget buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: _autovalidateMode,
      child: Scrollbar(
        child: SingleChildScrollView(
          dragStartBehavior: DragStartBehavior.down,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 24.0),
              TextFormField(
                style: TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person), hintText: 'email'),
                onSaved: (String value) {
                  account.name = value;
                },
                validator: _validateName,
              ),
              const SizedBox(height: 24.0),
              PasswordField(
                fieldKey: _passwordFieldKey,
                hintText: 'password',
                onSaved: (String value) {
                  account.password = value;
                },
              ),
              const SizedBox(height: 24.0),
              Container(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: Text('forget'),
                    onTap: () {
                      Navigator.pushNamed(context, '/reset_pwd_username',
                          arguments: {'username': account.name, 'token': 'to'});
                    },
                  )),
              const SizedBox(height: 24.0),
              FlatButton(
                color: Colors.lightBlue,
                child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    child: Text(
                      'sign in',
                      style: const TextStyle(color: Colors.white),
                    )),
                onPressed: _handleSubmitted,
              ),
              const SizedBox(height: 24.0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
        child: Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Builder(builder: buildForm),
    ));
    return Scaffold(
        appBar: AppBar(
          title: Text('sign in'),
        ),
        body: content);
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    this.fieldKey,
    this.hintText,
    this.labelText,
    this.helperText,
    this.onSaved,
    this.validator,
    this.onFieldSubmitted,
  });

  final Key fieldKey;
  final String hintText;
  final String labelText;
  final String helperText;
  final FormFieldSetter<String> onSaved;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onFieldSubmitted;

  @override
  _PasswordFieldState createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.fieldKey,
      style: TextStyle(color: Colors.white),
      obscureText: _obscureText,
      onSaved: widget.onSaved,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.lock),
        hintText: widget.hintText,
        labelText: widget.labelText,
        helperText: widget.helperText,
        suffixIcon: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
          child: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            semanticLabel: _obscureText ? 'show password' : 'hide password',
          ),
        ),
      ),
    );
  }
}

class AuthResp {
  final String token;
  final String username;

  AuthResp({@required this.token, @required this.username});
}

extension SignInExt on Api {
  Future<AuthResp> signInWithPwd(
      {@required String username, @required String password}) async {
    final resp = await post('/signin', {
      'username': username,
      'password': password,
    });
    final Map<String, String> profile = (resp['profile'] as Map)?.cast();
    return AuthResp(token: resp['token'], username: profile['username']);
  }
}
