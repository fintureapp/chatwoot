import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions';
import KanbanSDRPage from './pages/KanbanSDRPage.vue';

const kanbanRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/kanban-sdr-ai'),
      name: 'kanban_sdr_index',
      meta: {
        // CONVERSATION_PERMISSIONS alone only matches custom roles;
        // administrator/agent live in ROLES (hasPermissions has no admin
        // bypass, so without ROLES the sidebar item and route are hidden
        // from regular users — same pattern as inbox/routes.js).
        permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      },
      component: KanbanSDRPage,
    },
  ],
};

export default kanbanRoutes;
