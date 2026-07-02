import { frontendURL } from 'dashboard/helper/URLHelper';
import { CONVERSATION_PERMISSIONS } from 'dashboard/constants/permissions';
import KanbanSDRPage from './pages/KanbanSDRPage.vue';

const kanbanRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/kanban-sdr-ai'),
      name: 'kanban_sdr_index',
      meta: {
        permissions: CONVERSATION_PERMISSIONS,
      },
      component: KanbanSDRPage,
    },
  ],
};

export default kanbanRoutes;
