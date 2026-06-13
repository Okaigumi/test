-- ============================================================
-- Revoke direct write access to sites / site_assignments (Phase 3-3)
-- Run in Supabase SQL Editor
--
-- Purpose:
--   Close direct INSERT / UPDATE on sites and site_assignments for
--   anon / authenticated. All writes now go through the Phase 3-1
--   secure RPCs (create_site_secure / update_site_secure /
--   deactivate_site_secure / set_site_assignment_secure /
--   replace_site_assignments_secure).
--
-- Prerequisites (all completed):
--   - admin-app.html migrated to secure RPCs (Phase 3-2-1)
--   - index.html migrated to secure RPCs (Phase 3-2-2)
--   - Production UI verified for both apps (create / edit /
--     assignment changes / deactivate all OK)
--
-- Scope notes:
--   - SELECT is KEPT (sites / site_assignments lists must stay readable
--     in admin-app, index, and genka-app). Do NOT revoke SELECT.
--   - DELETE is OUT OF SCOPE (logical-delete operation only; physical
--     DELETE policies were already removed in a prior phase).
--   - Does NOT touch existing RLS policies, existing RPCs, or table
--     definitions.
--   - REVOKE ALL is intentionally NOT used; only INSERT / UPDATE are
--     revoked, explicitly.
-- ============================================================

REVOKE INSERT ON public.sites            FROM anon, authenticated;
REVOKE UPDATE ON public.sites            FROM anon, authenticated;
REVOKE INSERT ON public.site_assignments FROM anon, authenticated;
REVOKE UPDATE ON public.site_assignments FROM anon, authenticated;
