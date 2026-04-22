import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/patient.dart';

class PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onTap;

  const PatientCard({
    super.key,
    required this.patient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                // Geometric Avatar - Bauhaus style
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      patient.displayName.isNotEmpty
                          ? patient.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Patient Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (patient.gender != null || patient.birthDate != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (patient.gender != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    patient.gender!.toLowerCase() == 'male'
                                        ? FontAwesomeIcons.mars
                                        : patient.gender!.toLowerCase() == 'female'
                                            ? FontAwesomeIcons.venus
                                            : FontAwesomeIcons.genderless,
                                    size: 14,
                                    color: const Color(0xFF7F8C8D),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    patient.gender!.toUpperCase(),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            if (patient.birthDate != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    FontAwesomeIcons.calendar,
                                    size: 12,
                                    color: const Color(0xFF7F8C8D),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDate(patient.birthDate!),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Geometric Arrow Icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final age = now.year - date.year;
      if (now.month < date.month ||
          (now.month == date.month && now.day < date.day)) {
        return '${age - 1} years old';
      }
      return '$age years old';
    } catch (e) {
      return dateString;
    }
  }
}

