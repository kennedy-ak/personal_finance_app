'use client';

import { useState } from 'react';
import { keys, useWrite } from '@/lib/data/hooks';
import { categoriesRepo } from '@/lib/data/repositories';
import { type Category, type CategoryKind } from '@/lib/domain/category';
import { hueFor } from '@/lib/present';
import { Button, Dialog, ErrorNote, Field, Input, cx } from './ui';

/** The 16 choices category_editor_sheet.dart offers, as slug → glyph. */
export const ICON_CHOICES: { slug: string; glyph: string; label: string }[] = [
  { slug: 'bus', glyph: '🚌', label: 'Bus' },
  { slug: 'restaurant', glyph: '🍽️', label: 'Restaurant' },
  { slug: 'grocery', glyph: '🛒', label: 'Groceries' },
  { slug: 'bolt', glyph: '⚡', label: 'Utilities' },
  { slug: 'phone', glyph: '📱', label: 'Phone' },
  { slug: 'home', glyph: '🏠', label: 'Home' },
  { slug: 'shopping', glyph: '🛍️', label: 'Shopping' },
  { slug: 'medical', glyph: '🩺', label: 'Medical' },
  { slug: 'school', glyph: '🎓', label: 'School' },
  { slug: 'gift', glyph: '🎁', label: 'Gift' },
  { slug: 'savings', glyph: '🐖', label: 'Savings' },
  { slug: 'cash', glyph: '💵', label: 'Cash' },
  { slug: 'work', glyph: '💼', label: 'Work' },
  { slug: 'business', glyph: '🏢', label: 'Business' },
  { slug: 'trending_up', glyph: '📈', label: 'Investment' },
  { slug: 'label', glyph: '🏷️', label: 'Label' },
];

/**
 * New or edit category — port of category_editor_sheet.dart. Renaming goes
 * through rename_category so existing transactions are relabelled too.
 */
export function CategoryEditor({
  open,
  kind,
  category,
  onClose,
  onSaved,
}: {
  open: boolean;
  kind: CategoryKind;
  category?: Category | null;
  onClose: () => void;
  onSaved?: (name: string) => void;
}) {
  const [name, setName] = useState(category?.name ?? '');
  const [icon, setIcon] = useState(category?.icon ?? 'label');
  const [error, setError] = useState<string | null>(null);

  const save = useWrite(
    async () => {
      const n = name.trim();
      if (!n) throw new Error('Give it a name');
      if (category) {
        if (n !== category.name) await categoriesRepo.rename(category.id, n);
        if (icon !== category.icon) await categoriesRepo.setIcon(category.id, icon);
      } else {
        await categoriesRepo.create({ name: n, kind, icon });
      }
    },
    [keys.categories, keys.transactions],
  );

  const k = category?.kind ?? kind;

  return (
    <Dialog open={open} onClose={onClose} title={category ? 'Edit category' : `New ${k} category`}>
      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          setError(null);
          save.mutate(undefined, {
            onSuccess: () => {
              onSaved?.(name.trim());
              onClose();
            },
            onError: (err) =>
              setError(
                /duplicate|unique|categories_user_id_kind_name_key/i.test(err.message)
                  ? `You already have a ${k} category called "${name.trim()}".`
                  : err.message,
              ),
          });
        }}
      >
        <Field label="Name">
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={k === 'income' ? 'Salary' : 'Transportation'}
            autoFocus
          />
        </Field>
        <fieldset>
          <legend className="mb-1.5 text-xs font-medium text-ink-muted">Icon</legend>
          <div className="grid grid-cols-8 gap-2">
            {ICON_CHOICES.map((c) => (
              <button
                key={c.slug}
                type="button"
                aria-label={c.label}
                aria-pressed={icon === c.slug}
                onClick={() => setIcon(c.slug)}
                className={cx(
                  'flex h-11 w-11 items-center justify-center rounded-full text-lg transition',
                  icon === c.slug ? 'ring-2 ring-brand-ink' : 'opacity-80 hover:opacity-100',
                )}
                style={{ background: `var(--gs-${hueFor(name || c.slug)})` }}
              >
                {c.glyph}
              </button>
            ))}
          </div>
          <p className="mt-2 text-xs text-ink-faint">
            Rows show the first letters of the name. The icon is used wherever there is room for one.
          </p>
        </fieldset>
        <ErrorNote error={error} />
        <div className="flex justify-end">
          <Button type="submit" busy={save.isPending}>
            Save
          </Button>
        </div>
      </form>
    </Dialog>
  );
}
