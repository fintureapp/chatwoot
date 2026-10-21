import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions';
import CustomersPage from './pages/CustomersPage.vue';

// Gestão dos Clientes: busca por nome/telefone/e-mail e perfil completo do
// cliente (mesmo modal do Histórico do Kanban). Mesmas permissões do Kanban.
const customersRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/gestao-clientes'),
      name: 'customers_index',
      meta: {
        permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      },
      component: CustomersPage,
    },
  ],
};

export default customersRoutes;
