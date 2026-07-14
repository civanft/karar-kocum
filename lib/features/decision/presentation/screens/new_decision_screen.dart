import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/limits.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../../core/theme/tokens.dart';
import '../../../templates/presentation/providers/template_providers.dart';
import '../../../templates/presentation/widgets/template_card.dart';
import '../../../templates/presentation/widgets/template_preview_sheet.dart';
import '../../domain/validators/decision_validator.dart';
import '../providers/decision_providers.dart';

class NewDecisionScreen extends ConsumerStatefulWidget {
  const NewDecisionScreen({super.key, this.initialTitle});
  final String? initialTitle;

  @override
  ConsumerState<NewDecisionScreen> createState() => _NewDecisionScreenState();
}

class _NewDecisionScreenState extends ConsumerState<NewDecisionScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);
  String? _errorText;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final failure = DecisionValidator.title(_controller.text);
    if (failure != null) {
      setState(() => _errorText = failure.message);
      return;
    }
    setState(() {
      _errorText = null;
      _submitting = true;
    });

    final result = await ref.read(createDecisionProvider)(
      ownerUid: ref.read(currentUidProvider),
      title: _controller.text,
    );

    if (!mounted) return;
    result.when(
      ok: (decision) {
        unawaited(
          ref.read(analyticsServiceProvider).logDecisionCreated(
                source: widget.initialTitle != null ? 'template' : 'blank',
              ),
        );
        context.pushReplacement('/decision/${decision.id}/edit');
      },
      err: (f) => setState(() {
        _submitting = false;
        _errorText = 'Karar oluşturulamadı, tekrar deneyin.';
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Karar')),
      body: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Neye karar vereceksin?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTokens.s4),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: Limits.titleMaxLength,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Örn. iPhone mu Samsung mu?',
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: AppTokens.s4),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Devam Et'),
            ),
            const SizedBox(height: AppTokens.s6),
            // A1-b: dönen kullanıcı için şablon şeridi.
            Text(
              'Ya da bir şablonla başla',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppTokens.s2),
            SizedBox(
              height: 132,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final template
                      in ref.watch(templateCatalogProvider).all())
                    Padding(
                      padding: const EdgeInsets.only(right: AppTokens.s2),
                      child: TemplateCard(
                        template: template,
                        compact: true,
                        onTap: () =>
                            showTemplatePreviewSheet(context, template),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
