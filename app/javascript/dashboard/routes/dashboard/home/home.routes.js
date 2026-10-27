import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import HomePage from './pages/HomePage.vue';

// Home: a primeira tela de todo usuário (defaultRedirectPage e o redirect do
// router apontam para cá). Mesmas permissões da lista de conversas; todos veem
// os números da conta inteira. Os filtros ficam na query da URL para sobreviver
// à ida e volta da conversa aberta a partir de um indicador.
const homeRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/inicio'),
      name: 'finture_home',
      meta: {
        permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      },
      component: HomePage,
    },
  ],
};

export default homeRoutes;
