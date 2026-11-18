"""Dated score explanations, never a fused diagnosis or preventive-efficacy score."""


def summary(context, language):
    if not context.personalization_enabled:
        return ''
    lines = []
    if context.mood and context.mood.mean_rating is not None:
        mood = context.mood
        lines.append({'en': f'Recorded mood: {mood.mean_rating:.1f}/5 across {mood.record_count} observed days, latest {mood.latest_date}.',
                      'ur': f'درج شدہ موڈ: {mood.mean_rating:.1f}/5، {mood.record_count} مشاہدہ شدہ دن، تازہ تاریخ {mood.latest_date}۔',
                      'roman_ur': f'Recorded mood: {mood.mean_rating:.1f}/5, {mood.record_count} observed din, latest {mood.latest_date}.'}[language])
        if mood.coverage_fraction < .7:
            lines.append({'en':'The window has sparse observations; missing days are not healthy defaults.',
                          'ur':'اس عرصے کے مشاہدات کم ہیں؛ غیر درج دن اچھے موڈ کا ثبوت نہیں۔',
                          'roman_ur':'Is window ke observations kam hain; missing din achhay mood ka saboot nahi.'}[language])
    for screen in context.screenings:
        lines.append(f'{screen.instrument.upper()} ({screen.completed_at.date()}): {screen.score}/{30 if screen.instrument == "epds" else 27}.'
                     + {'en':' Screening, not diagnosis.' + (' Earlier result, not current state.' if screen.stale else ''),
                        'ur':' اسکریننگ، تشخیص نہیں۔' + (' پرانا نتیجہ، موجودہ حالت نہیں۔' if screen.stale else ''),
                        'roman_ur':' Screening, tashkhees nahi.' + (' Purana result, current halat nahi.' if screen.stale else '')}[language])
    if context.risk:
        risk = context.risk
        lines.append({'en': f'Research model ({risk.generated_at.date()}): {risk.probability*100:.1f}% source-association estimate, not a diagnosis or validated future forecast.' + (' This result is stale.' if risk.stale else ''),
                      'ur': f'تحقیقی ماڈل ({risk.generated_at.date()}): {risk.probability*100:.1f}% سابقہ ڈیٹا سے تعلق کا اندازہ، تشخیص یا توثیق شدہ مستقبل کی پیش گوئی نہیں۔' + (' یہ نتیجہ پرانا ہے۔' if risk.stale else ''),
                      'roman_ur': f'Research model ({risk.generated_at.date()}): {risk.probability*100:.1f}% source association ka andaza, tashkhees ya validated future forecast nahi.' + (' Ye result purana hai.' if risk.stale else '')}[language])
    if context.sentiment and context.sentiment.mean_score is not None:
        item = context.sentiment
        lines.append({'en': f'Journal sentiment estimate: {item.mean_score:.2f} on −1 to +1 across {item.record_count} entries; not a clinical distress probability.',
                      'ur': f'جرنل کے جذبات کا اندازہ: {item.mean_score:.2f}، −1 سے +1، {item.record_count} اندراجات؛ طبی پریشانی کا امکان نہیں۔',
                      'roman_ur': f'Journal sentiment andaza: {item.mean_score:.2f}, -1 se +1, {item.record_count} entries; clinical distress probability nahi.'}[language])
    return '\n'.join(lines)
