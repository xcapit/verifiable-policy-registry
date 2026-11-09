# Localisation and accessibility

*CC BY 4.0 · Proposal package for a school pilot · v0.3 preparation*

What people at schools and ministries will read and use, in which languages, and how it is made accessible. **No translation exists yet.** Repository documentation is in English; everything below in other languages is Planned.

## Who reads what

| Audience | Material | Language need | Status |
| --- | --- | --- | --- |
| Students and teachers | Block page: why a site is blocked, how to ask for a review | Main language(s) of the pilot country | Planned (VPR-017: Spanish and Portuguese first) |
| Teachers and school focal points | Appeal form | Same as block page | Planned (VPR-017) |
| School focal points | One-page guide: what changes, whom to call, what is not collected | Same as block page | Planned (M2) |
| Parents and community | Short notice: what the filter does and does not do, and how to see the public policy | Same as block page | Planned (M2), wording to be agreed with the ministry |
| Ministry and Giga staff | Policy cycle guide for signers, dashboard guide | Spanish or Portuguese, English | Planned (M2) |
| Operator and provider staff | Runbooks | English, with the language of the operating team | Planned (M3) |
| Independent reviewer | Test kit guide | English and the reviewer's working language | Planned (M2) |

The policy document itself (categories, blocked and excepted domains with reasons) is published as written by the governing institutions; its reasons should be written in the country's language so that the public can read them.

## Translation approach

- Strings for the block page and appeal form are kept in a translation file, not embedded in code (acceptance criterion of VPR-017).
- Translations are made or reviewed by native speakers familiar with school contexts, not only by machine translation.
- Indigenous or minority languages are added where the ministry identifies the need; this is an open question for the ministry ([OPEN_QUESTIONS_FOR_GIGA.md](OPEN_QUESTIONS_FOR_GIGA.md)).
- `publiccode.yml` will declare additional languages only after translated material exists.

## Accessibility of the block page and appeal form

Target: WCAG 2.1 level AA for the block page and appeal form.

- Works without JavaScript and on old, low-end browsers and phones.
- Small page weight so that it loads on slow and satellite links.
- Screen-reader compatible; sufficient contrast; text resizable without loss of content.
- No account, email or phone number required to appeal.
- No CAPTCHA that blocks assistive technology; rate limiting is done server-side instead.

## Low literacy and young users

- The block page uses short sentences and a simple icon showing that the site is blocked by the school network, not by the child's own fault.
- The message never accuses or warns the child; it explains that the site is not available on the school network and that a teacher can ask for a review.
- Students are not asked to submit appeals themselves or to type any personal information; appeals are meant for teachers and staff.
- The block page does not show which category triggered the block when that category could embarrass or stigmatise (for example adult content); a generic message is shown instead. To be confirmed in the scope charter.

## Training

| Who | Content | Format | Status |
| --- | --- | --- | --- |
| Governing signers | Approving and renewing a policy, answering an appeal, rotating a key | Rehearsal on the test network (Stage 0) | Planned (M1) |
| School focal points | What changes, how to report, rollback | Short session and one-page guide | Planned (M2) |
| Operator staff | Runbooks, incident response, privacy constraints | Hands-on | Planned (M2–M3) |
| Reviewer | Test kit, attestation, reports | Hands-on | Planned (M2) |

## Checklist used in evaluation

- [ ] Block page available in the pilot language(s)
- [ ] Appeal form usable with a screen reader
- [ ] Block page loads on the slowest pilot link
- [ ] Appeal possible without any account
- [ ] School guide distributed to every alpha school
- [ ] Community notice approved by the ministry
