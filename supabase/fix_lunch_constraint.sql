-- =============================================================================
-- Fix: 03_seed_routine.sql fails with classes_check1 violation
-- =============================================================================
-- Cause: the imported university routine has 19 real labs that start at period 2
-- (P3, 11:10-12:30) and run 2 periods into P4 (13:00-14:20). The original rule
-- `not (period < 3 and period + periods > 3)` rejects every one of them.
--
-- Fix: relax the rule to allow exactly that case. New shift requests are still
-- blocked from crossing lunch by check_move() in 01_schema.sql.
--
-- Run this in Supabase SQL Editor (safe to re-run), then re-run 03_seed_routine.sql.
-- =============================================================================

-- Drop every table-level check we might have created, so this script is safe
-- to run more than once (a previous partial run may have added some of them).
alter table classes drop constraint if exists classes_check1;
alter table classes drop constraint if exists classes_check2;
alter table classes drop constraint if exists classes_periods_check;
alter table classes drop constraint if exists classes_lunch_check;

alter table classes add constraint classes_periods_check
  check (period + periods <= 6);

alter table classes add constraint classes_lunch_check
  check (not (period < 2 and period + periods > 3));

-- Optional: only if a previous attempt left partial rows behind.
-- Check first with:  select count(*) from classes where semester='Fall 2026';
-- delete from classes where semester='Fall 2026';

-- Verify the relaxed rule is installed:
-- select conname, pg_get_constraintdef(oid) from pg_constraint
-- where conrelid = 'classes'::regclass and contype = 'c';
