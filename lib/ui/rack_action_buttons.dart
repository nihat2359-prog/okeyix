import 'package:flutter/material.dart';

class RackActionButtons extends StatefulWidget {
  final Function(int index) onSelected;

  const RackActionButtons({super.key, required this.onSelected});

  @override
  State<RackActionButtons> createState() => _RackActionButtonsState();
}

class _RackActionButtonsState extends State<RackActionButtons> {
  int selectedIndex = 0;
  final List<String> labels = ['Seri Diz', 'Çifte Diz', 'Çifte Git'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 122,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xCC141A20), Color(0xAA0F141A)],
        ),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final isSelected = selectedIndex == index;
          return Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => selectedIndex = index);
                  widget.onSelected(index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0x22D4AF37) : Colors.transparent,
                    borderRadius: BorderRadius.vertical(
                      top: index == 0 ? const Radius.circular(14) : Radius.zero,
                      bottom: index == labels.length - 1
                          ? const Radius.circular(14)
                          : Radius.zero,
                    ),
                  ),
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: isSelected ? const Color(0xFFD4AF37) : Colors.white,
                    ),
                  ),
                ),
              ),
              if (index != labels.length - 1)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0x22FFFFFF),
                ),
            ],
          );
        }),
      ),
    );
  }
}
