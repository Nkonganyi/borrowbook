-- Correction / void log (Roadmap P1.3)
--
-- Scoped precursor to the full audit log in P4: only covers edits/deletes
-- of borrow_items, and only requires a reason when the item already has at
-- least one payment recorded against it (i.e. money has already changed
-- hands, so silently rewriting the item afterward is a real risk).
--
-- Same append-only philosophy as payments: no UPDATE/DELETE policy, so a
-- correction can never itself be quietly corrected.

create table if not exists borrow_item_changes (
  id uuid primary key default gen_random_uuid(),
  -- nullable + set null on delete: if the item itself gets deleted, this
  -- log entry survives as the record of *why*, it just loses the live FK.
  borrow_item_id uuid references borrow_items(id) on delete set null,
  customer_id uuid not null references customers(id) on delete cascade,
  action text not null check (action in ('edit', 'delete')),
  reason text not null,
  changed_by text not null,
  old_item_name text,
  old_price numeric,
  new_item_name text,
  new_price numeric,
  created_at timestamptz not null default now()
);

create index if not exists idx_borrow_item_changes_customer_id on borrow_item_changes(customer_id);
create index if not exists idx_borrow_item_changes_borrow_item_id on borrow_item_changes(borrow_item_id);

alter table borrow_item_changes enable row level security;

create policy "Authenticated users can view change log"
  on borrow_item_changes for select
  to authenticated
  using (true);

create policy "Authenticated users can insert change log entries"
  on borrow_item_changes for insert
  to authenticated
  with check (true);

-- Intentionally no UPDATE or DELETE policy: append-only, same as payments.
