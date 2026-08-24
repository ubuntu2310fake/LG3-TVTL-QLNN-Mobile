import 'package:flutter/material.dart';

class CustomNumpad extends StatefulWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  final String? title;

  const CustomNumpad({
    Key? key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmit,
    this.title,
  }) : super(key: key);

  @override
  State<CustomNumpad> createState() => _CustomNumpadState();
}

class _CustomNumpadState extends State<CustomNumpad> with SingleTickerProviderStateMixin {
  late String _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.controller?.text ?? widget.initialValue ?? "";
  }

  void _onKeyPress(String val) {
    if (val == 'C') {
      _currentValue = '';
    } else if (val == '<') {
      if (_currentValue.isNotEmpty) {
        _currentValue = _currentValue.substring(0, _currentValue.length - 1);
      }
    } else {
      if (val == '.' && _currentValue.contains('.')) return;
      _currentValue += val;
    }
    
    if (widget.controller != null) {
      widget.controller!.text = _currentValue;
      widget.controller!.selection = TextSelection.fromPosition(TextPosition(offset: _currentValue.length));
    }
    if (widget.onChanged != null) {
      widget.onChanged!(_currentValue);
    }
    setState(() {});
  }

  Widget _buildKey(BuildContext context, String val, {Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: _NumpadButton(
          text: val,
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          onTap: val == 'OK' ? (widget.onSubmit ?? () {}) : () => _onKeyPress(val),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          // Display area ALWAYS shown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.title ?? '', style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(
                  _currentValue.isEmpty ? '0' : _currentValue,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
          ),
          Expanded(child: Row(children: [_buildKey(context, '1'), _buildKey(context, '2'), _buildKey(context, '3')])),
          Expanded(child: Row(children: [_buildKey(context, '4'), _buildKey(context, '5'), _buildKey(context, '6')])),
          Expanded(child: Row(children: [_buildKey(context, '7'), _buildKey(context, '8'), _buildKey(context, '9')])),
          Expanded(
            child: Row(
              children: [
                _buildKey(context, 'C', color: Colors.red.withValues(alpha: 0.2)),
                _buildKey(context, '0'),
                _buildKey(context, '.'),
                _buildKey(context, '<'),
              ],
            ),
          ),
          if (widget.onSubmit != null)
            Expanded(
              child: Row(
                children: [
                  _buildKey(context, 'OK', color: Colors.blue.withValues(alpha: 0.2)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NumpadButton extends StatefulWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _NumpadButton({Key? key, required this.text, required this.color, required this.onTap}) : super(key: key);

  @override
  State<_NumpadButton> createState() => _NumpadButtonState();
}

class _NumpadButtonState extends State<_NumpadButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                offset: const Offset(0, 2),
                blurRadius: 2,
              )
            ]
          ),
          child: Center(
            child: widget.text == '<'
                ? const Icon(Icons.backspace_outlined)
                : Text(widget.text, style: TextStyle(fontSize: 24, fontWeight: widget.text == 'OK' || widget.text == 'C' ? FontWeight.bold : FontWeight.normal)),
          ),
        ),
      ),
    );
  }
}
