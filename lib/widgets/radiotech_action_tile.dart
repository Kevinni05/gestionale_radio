import 'package:flutter/material.dart';
import '../theme/radiotech_glass.dart';
import '../theme/radiotech_theme.dart';

class RadioTechActionTile extends StatefulWidget {
  const RadioTechActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  State<RadioTechActionTile> createState() => _RadioTechActionTileState();
}

class _RadioTechActionTileState extends State<RadioTechActionTile> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return AnimatedScale(
      scale: _pressed ? .98 : 1,
      duration: duration,
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _pressed ? const Color(0x30FF6363) : Colors.transparent,
              blurRadius: 18,
            ),
          ],
        ),
        child: RadioTechGlass(
          highlight: _pressed,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x0AFFFFFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: RadioTechTheme.border),
                      ),
                      child: Icon(
                        widget.icon,
                        color: RadioTechTheme.mist,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: scaler.scale(14) * 2.6,
                      child: Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: scaler.scale(11) * 2.7,
                      child: Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: RadioTechTheme.muted,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
