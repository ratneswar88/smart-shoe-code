import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Card(
            color: cs.surfaceContainerHigh,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Tutorial\n\n"
                "1) Tap Scan & Connect on Dashboard to connect to the shoe.\n"
                "2) Watch live metrics (RSSI, roll/pitch/yaw, temp, steps).\n"
                "3) Graphs tab shows smooth lines for R/P/Y and gait phases.\n"
                "4) Training tab: choose a label, Start → Stop (auto-saves CSV),\n"
                "   then Train & Save to create a model JSON.\n"
                "5) Share last CSV from Training tab or browse app files.\n\n"
                "Tip: use the Palette icon to change theme/color.",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                              SOFTMAX CLASSIFIER                             */
/* -------------------------------------------------------------------------- */