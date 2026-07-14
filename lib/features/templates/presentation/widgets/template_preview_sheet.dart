import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../domain/entities/decision_template.dart';
import '../providers/template_decision_creator.dart';

/// Şablon önizleme sheet'i (SPRINT-A §1.1): taahhütten ÖNCE içerik gösterir —
/// kullanıcı ne alacağını görmeden karar YARATILMAZ (çöp taslak +
/// maxDecisionsPerUser kotası israfı önlenir).
Future<void> showTemplatePreviewSheet(
  BuildContext context,
  DecisionTemplate template,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _TemplatePreviewContent(template: template),
  );
}

class _TemplatePreviewContent extends ConsumerStatefulWidget {
  const _TemplatePreviewContent({required this.template});

  final DecisionTemplate template;

  @override
  ConsumerState<_TemplatePreviewContent> createState() =>
      _TemplatePreviewContentState();
}

class _TemplatePreviewContentState
    extends ConsumerState<_TemplatePreviewContent> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.template.title);
  bool _creating = false;
  String? _errorText;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _createFromTemplate() async {
    if (_creating) return; // çift dokunuş tek karar üretir
    setState(() {
      _creating = true;
      _errorText = null;
    });

    // İş mantığı TemplateDecisionCreator'da (birim testli) — sheet yalnız
    // durum + navigasyon tutar.
    final decisionId = await ref.read(templateDecisionCreatorProvider)(
      ownerUid: ref.read(currentUidProvider),
      title: _titleController.text,
      template: widget.template,
    );

    if (!mounted) return;
    if (decisionId == null) {
      setState(() {
        _creating = false;
        _errorText = 'Karar oluşturulamadı, tekrar deneyin.';
      });
      return;
    }
    // Sheet'i kapat + editöre git (Seçenekler sekmesi açık gelir;
    // kriterler zaten dolu — "sonraki boş iş" ilkesi).
    context.pop();
    unawaited(context.push('/decision/$decisionId/edit'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = widget.template;

    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.s4,
        right: AppTokens.s4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppTokens.s4,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            '${template.emoji}  ${template.title}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            template.description,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTokens.s4),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Kararının adı',
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          Text('Hazır kriterler', style: theme.textTheme.titleSmall),
          for (final criterion in template.criteria)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(criterion.name),
              trailing: Text(
                'Önem ${criterion.weight}/10',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (template.sampleOptions.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s2),
            Text('Örnek seçenekler', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTokens.s2),
            Wrap(
              spacing: AppTokens.s2,
              children: [
                for (final option in template.sampleOptions)
                  Chip(label: Text(option)),
              ],
            ),
          ],
          const SizedBox(height: AppTokens.s4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _creating
                      ? null
                      : () {
                          final location =
                              TemplateDecisionCreator.blankStartLocation(
                            _titleController.text,
                          );
                          context.pop();
                          context.push(location);
                        },
                  child: const Text('Boş başla'),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: FilledButton(
                  onPressed: _creating ? null : _createFromTemplate,
                  child: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Bu şablonla başla'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
