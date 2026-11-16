'use client';

import { useState } from 'react';
import { CategoryEditor, ICON_CHOICES } from '@/components/category-editor';
import { Icon } from '@/components/icons';
import { Button, Confirm, Dialog, Empty, ErrorNote, Eyebrow, Glyph, Loading, Tabs } from '@/components/ui';
import { keys, useCategories, useWrite } from '@/lib/data/hooks';
import { categoriesRepo, isCategoriesTableMissing } from '@/lib/data/repositories';
import { type Category, type CategoryKind } from '@/lib/domain/category';
import { hueFor, plural } from '@/lib/present';

const CAT_KEYS = [keys.categories] as const;

/** Port of categories/presentation/categories_screen.dart. */
export default function CategoriesPage() {
  const { data, isLoading, error } = useCategories();
  const [kind, setKind] = useState<CategoryKind>('expense');
  const [editing, setEditing] = useState<Category | 'new' | null>(null);
  const [actions, setActions] = useState<Category | null>(null);
  const [deleting, setDeleting] = useState<{ c: Category; uses: number } | null>(null);
  const [actionError, setActionError] = useState<unknown>(null);

  const setHidden = useWrite(async ({ c, hidden }: { c: Category; hidden: boolean }) => categoriesRepo.setHidden(c.id, hidden), CAT_KEYS);
  const seed = useWrite(async () => categoriesRepo.restoreDefaults(), CAT_KEYS);
  const remove = useWrite(async (id: string) => categoriesRepo.remove(id), CAT_KEYS);

  if (isLoading) return <Loading />;
  if (error) {
    return (
      <ErrorNote
        error={
          isCategoriesTableMissing(error)
            ? 'Categories are not set up on the server yet. Run 0007_custom_categories.sql in the Supabase SQL editor, then reload.'
            : error
        }
      />
    );
  }

  const ofKind = (data ?? []).filter((c) => c.kind === kind);
  const shown = ofKind.filter((c) => !c.isHidden);
  const hidden = ofKind.filter((c) => c.isHidden);
  const iconFor = (c: Category) => ICON_CHOICES.find((i) => i.slug === c.icon)?.glyph;

  return (
    <>
      <header className="mb-4 flex items-end justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Categories</h1>
        <Button variant="secondary" onClick={() => setEditing('new')}>
          <Icon name="plus" width={16} height={16} /> New
        </Button>
      </header>

      <Tabs<CategoryKind>
        label="Category kind"
        value={kind}
        onChange={setKind}
        options={[
          { value: 'expense', label: 'Spending' },
          { value: 'income', label: 'Income' },
        ]}
      />

      <ErrorNote error={actionError} />

      {ofKind.length === 0 ? (
        <Empty title="No categories yet">
          <p>
            Without categories, spending reports have nothing to group by. The default list covers trotro, food,
            utilities, airtime and sending money.
          </p>
          <div className="mt-4 flex justify-center gap-2">
            <Button busy={seed.isPending} onClick={() => seed.mutate()}>
              Use the default list
            </Button>
            <Button variant="secondary" onClick={() => setEditing('new')}>
              Or create my own
            </Button>
          </div>
        </Empty>
      ) : (
        <>
          <ul className="rounded-2xl border border-hairline bg-card p-1">
            {shown.map((c) => (
              <li key={c.id}>
                <button
                  type="button"
                  onClick={() => setActions(c)}
                  aria-label={`${c.name} options`}
                  className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left hover:bg-recessed"
                >
                  <Glyph name={c.name} hue={hueFor(c.name)} />
                  <span className="min-w-0 flex-1">
                    {c.isBuiltin && <Eyebrow>Built in</Eyebrow>}
                    <span className="block truncate text-sm font-medium">
                      {c.name} {iconFor(c) && <span aria-hidden>{iconFor(c)}</span>}
                    </span>
                  </span>
                  <span aria-hidden className="text-ink-faint">⋮</span>
                </button>
              </li>
            ))}
            {shown.length === 0 && <li className="px-4 py-4 text-sm text-ink-muted">Everything here is hidden.</li>}
          </ul>

          {hidden.length > 0 && (
            <section className="mt-8">
              <div className="mb-1 flex items-baseline gap-2">
                <h2 className="text-sm font-semibold">Hidden</h2>
                <Eyebrow>{hidden.length}</Eyebrow>
              </div>
              <p className="mb-3 text-xs text-ink-muted">Still on old transactions, no longer offered when you add one.</p>
              <ul className="rounded-2xl border border-hairline bg-card p-1">
                {hidden.map((c) => (
                  <li key={c.id} className="flex items-center gap-3 px-3 py-2.5">
                    <Glyph name={c.name} hue={hueFor(c.name)} />
                    <span className="flex-1 text-sm text-ink-muted">{c.name}</span>
                    <Button variant="ghost" onClick={() => setHidden.mutate({ c, hidden: false })} aria-label={`Restore ${c.name}`}>
                      Restore
                    </Button>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </>
      )}

      <Dialog open={actions !== null} onClose={() => setActions(null)} title={actions?.name ?? ''}>
        {actions && (
          <div className="space-y-1">
            <ActionRow
              title="Rename or change icon"
              onClick={() => {
                setEditing(actions);
                setActions(null);
              }}
            />
            <ActionRow
              title={actions.isHidden ? 'Show it again' : 'Hide from pickers'}
              detail={actions.isHidden ? undefined : 'Old transactions keep the label. It just stops being offered.'}
              onClick={() => {
                setHidden.mutate({ c: actions, hidden: !actions.isHidden });
                setActions(null);
              }}
            />
            <ActionRow
              title="Delete"
              danger
              onClick={async () => {
                const c = actions;
                setActions(null);
                setActionError(null);
                try {
                  setDeleting({ c, uses: await categoriesRepo.usageCount(c.id) });
                } catch (e) {
                  setActionError(e);
                }
              }}
            />
          </div>
        )}
      </Dialog>

      <CategoryEditor
        key={editing === null ? 'closed' : editing === 'new' ? `new-${kind}` : editing.id}
        open={editing !== null}
        kind={kind}
        category={editing === 'new' ? null : editing}
        onClose={() => setEditing(null)}
      />

      <Confirm
        open={deleting !== null}
        title={`Delete "${deleting?.c.name ?? ''}"?`}
        body={
          deleting?.uses
            ? `${plural(deleting.uses, 'transaction')} ${deleting.uses === 1 ? 'is' : 'are'} filed under it. ${deleting.uses === 1 ? 'It keeps' : 'They keep'} the label, but it stops being offered. Hiding does the same thing and is reversible.`
            : 'Nothing is filed under it, so this removes it cleanly.'
        }
        confirmLabel="Delete"
        danger
        busy={remove.isPending}
        error={remove.error}
        onClose={() => setDeleting(null)}
        onConfirm={() => deleting && remove.mutate(deleting.c.id, { onSuccess: () => setDeleting(null) })}
      />
    </>
  );
}

function ActionRow({
  title,
  detail,
  danger,
  onClick,
}: {
  title: string;
  detail?: string;
  danger?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="block w-full rounded-xl px-3 py-2.5 text-left hover:bg-recessed"
    >
      <span className={danger ? 'text-expense' : 'font-medium'}>{title}</span>
      {detail && <span className="mt-0.5 block text-xs text-ink-muted">{detail}</span>}
    </button>
  );
}
