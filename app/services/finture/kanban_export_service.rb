# Exportação do Kanban (board ou histórico) em Excel (.xlsx), processada no
# servidor sobre o conjunto filtrado COMPLETO (sem o cap de 1000 do board).
# Os dados vêm de Finture::KanbanExportDataset (uma linha por contato); aqui
# fica só a planilha com identidade Finture, no mesmo padrão visual dos
# relatórios de Saúde: aba "Principal" (logo, título com filete laranja e
# blocos label/valor com faixa preta de seção) e aba "Contatos" (tabela com
# cabeçalho preto, zebra bege, filtro automático, cabeçalho congelado e tipos
# nativos — datas, moeda e telefone como texto, sem notação científica).
# Paleta e estilos: Finture::KanbanExportStyles.
class Finture::KanbanExportService
  TIMEZONE = 'America/Sao_Paulo'.freeze
  LOGO_PATH = Rails.public_path.join('brand-assets/logo.png')
  # Aba Contatos: linhas 1–4 = título, subtítulo, filete e respiro; linha 5 = cabeçalho.
  HEADER_ROW = 5

  # [título, largura, tipo] — tipo: :text | :int | :date | :money | :outcome
  COLUMNS = [
    ['Nome', 32, :text], ['Telefone', 18, :text], ['E-mail', 30, :text], ['Responsável', 22, :text],
    ['Produto', 20, :text], ['Etapa', 20, :text], ['Desfecho', 14, :outcome], ['Motivo da perda', 24, :text],
    ['Volume (R$)', 16, :money], ['Próxima ação', 36, :text], ['Qtd. de demandas', 12, :int],
    ['IDs das demandas', 18, :text], ['Primeira demanda em', 19, :date], ['Última atividade em', 19, :date],
    ['Fechado em', 19, :date], ['ID do contato', 12, :int]
  ].freeze
  AXLSX_TYPES = { text: :string, outcome: :string, int: :integer, date: :time, money: :float }.freeze

  # scope: conversas já recortadas por board/histórico e permissão (sem limit).
  # params: scope, q, product, stage, assignee_id, created_from, created_to, outcome.
  pattr_initialize [:scope!, :params!, :inbox!, :kanban_type!]

  def perform
    package = Axlsx::Package.new
    package.use_shared_strings = true
    workbook = package.workbook
    styles = Finture::KanbanExportStyles.build(workbook)
    workbook.add_worksheet(name: 'Principal') { |sheet| build_cover_sheet(sheet, styles) }
    workbook.add_worksheet(name: 'Contatos') { |sheet| build_data_sheet(sheet, styles) }
    package.to_stream.read
  end

  def filename
    origin = history? ? 'historico' : 'board'
    "finture-contatos-#{origin}-#{inbox.name.to_s.parameterize.presence || inbox.id}-#{now.strftime('%Y%m%d-%H%M')}.xlsx"
  end

  private

  def dataset
    @dataset ||= Finture::KanbanExportDataset.new(scope: scope, params: params, inbox: inbox, kanban_type: kanban_type)
  end

  delegate :rows, :records, :stage_label, to: :dataset

  # ---- Aba Principal (capa) --------------------------------------------------

  def build_cover_sheet(sheet, styles)
    sheet.sheet_view.show_grid_lines = false
    sheet.sheet_pr.tab_color = Finture::KanbanExportStyles::ORANGE
    sheet.column_widths 11, 34, 90
    add_title_block(sheet, styles, cover_subtitle, last_index: 2, logo: true)
    add_section(sheet, styles, 'RESUMO DO RECORTE', summary_pairs)
    add_section(sheet, styles, 'FILTROS APLICADOS', filter_pairs)
    add_section(sheet, styles, 'COMO LER ESTA PLANILHA', reading_pairs)
    sheet.page_setup.set(orientation: :portrait, fit_to_width: 1, fit_to_height: 0)
  end

  # Faixa preta com o nome da seção + linhas "Rótulo | Valor" (zebra bege),
  # como nos blocos "DADOS DA OPERADORA / DO CLIENTE" dos relatórios de Saúde.
  def add_section(sheet, styles, title, pairs)
    sheet.add_row [nil, title, nil], style: [nil, styles[:section], styles[:section]], height: 24
    sheet.merge_cells("B#{sheet.rows.size}:C#{sheet.rows.size}")
    pairs.each_with_index do |(label, value, accent), index|
      zebra = index.odd? ? '_zebra' : ''
      value_style = styles[:"#{accent || :value}#{zebra}"]
      sheet.add_row [nil, label, value], style: [nil, styles[:"label#{zebra}"], value_style], height: 22,
                                         types: [:string, :string, value.is_a?(Numeric) ? :integer : :string]
    end
    sheet.add_row [], height: 14
  end

  def summary_pairs
    [
      ['Caixa', inbox.name],
      ['Origem', history? ? 'Histórico (fechados)' : 'Board (em andamento)'],
      ['Tipo da caixa', kanban_type == 'operacional' ? 'Operacional' : 'Comercial'],
      ['Contatos', rows.size, :strong],
      ['Demandas', records.size, :strong],
      ['Gerado em', "#{now.strftime('%d/%m/%Y %H:%M')} (Brasília)"]
    ]
  end

  def filter_pairs # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    active = []
    active << ['Busca', params[:q]] if params[:q].present?
    active << ['Produto', params[:product]] if params[:product].present?
    active << ['Etapa', stage_label(params[:stage])] if params[:stage].present?
    active << ['Responsável', User.find_by(id: params[:assignee_id])&.available_name] if params[:assignee_id].present?
    active << ['Criado de', br_date(params[:created_from])] if params[:created_from].present?
    active << ['Criado até', br_date(params[:created_to])] if params[:created_to].present?
    active << ['Desfecho', params[:outcome] == 'won' ? 'Ganho' : 'Perdido'] if params[:outcome].present?
    active.any? ? active.map { |label, value| [label, value, :accent] } : [['Filtros', 'Nenhum (recorte completo da aba)']]
  end

  def reading_pairs
    [
      ['Linhas', 'Uma linha por contato, deduplicado por ID do contato → telefone → e-mail.'],
      ['Contexto', 'Etapa, responsável, produto e desfecho vêm da demanda mais recente do contato.'],
      ['Demais demandas', 'Ficam em "Qtd. de demandas" e "IDs das demandas" — nada é perdido.'],
      ['Datas', 'Hora de parede de Brasília (o Excel não guarda fuso horário).']
    ]
  end

  def cover_subtitle
    origin = history? ? 'Histórico (fechados)' : 'Board (em andamento)'
    "#{inbox.name} · #{origin} · gerado em #{now.strftime('%d/%m/%Y %H:%M')}"
  end

  # ---- Aba Contatos (tabela) -------------------------------------------------

  def build_data_sheet(sheet, styles)
    sheet.sheet_view.show_grid_lines = false
    sheet.sheet_pr.tab_color = Finture::KanbanExportStyles::BLACK
    add_title_block(sheet, styles, table_subtitle, last_index: COLUMNS.size - 1)
    sheet.add_row COLUMNS.map(&:first), style: styles[:header], height: 28
    add_data_rows(sheet, styles)
    sheet.column_widths(*COLUMNS.pluck(1))
    freeze_header(sheet)
    sheet.page_setup.set(orientation: :landscape, fit_to_width: 1, fit_to_height: 0)
  end

  def add_data_rows(sheet, styles)
    types = COLUMNS.map { |col| AXLSX_TYPES[col[2]] }
    rows.each_with_index do |row, index|
      sheet.add_row row, style: row_styles(styles, row, index), types: types, height: 20
    end
    sheet.auto_filter = "A#{HEADER_ROW}:#{last_column}#{HEADER_ROW + rows.size}" if rows.any?
  end

  def row_styles(styles, row, index)
    zebra = index.odd? ? '_zebra' : ''
    COLUMNS.each_with_index.map do |(_, _, type), col|
      key = type == :outcome ? outcome_style_key(row[col]) : type
      styles[:"#{key}#{zebra}"]
    end
  end

  def outcome_style_key(value)
    case value
    when 'Ganho' then :won
    when 'Perdido' then :lost
    else :neutral
    end
  end

  def freeze_header(sheet)
    sheet.sheet_view.pane do |pane|
      pane.state = :frozen
      pane.y_split = HEADER_ROW
      pane.active_pane = :bottom_left
      pane.top_left_cell = "A#{HEADER_ROW + 1}"
    end
  end

  def table_subtitle
    "#{inbox.name} · #{rows.size} contato(s) · #{records.size} demanda(s) · #{short_filters}"
  end

  def short_filters
    pairs = filter_pairs
    return 'sem filtros' if pairs.size == 1 && pairs.first.first == 'Filtros'

    "filtros: #{pairs.map { |label, value| "#{label.downcase} #{value}" }.join(' · ')}"
  end

  # ---- Elementos compartilhados ----------------------------------------------

  # Título "Contatos", subtítulo cinza e filete laranja (linha 3), mesclados até
  # a coluna `last_index`. Com `logo`, a coluna A fica como calha e recebe a logo.
  def add_title_block(sheet, styles, subtitle, last_index:, logo: false)
    first_index = logo ? 1 : 0
    last_col = Axlsx.col_ref(last_index)
    prefix = Array.new(first_index)
    sheet.add_row prefix + ['Contatos'], style: prefix + [styles[:title]], height: 34
    sheet.add_row prefix + [subtitle], style: prefix + [styles[:subtitle]], height: 20
    sheet.add_row Array.new(last_index + 1), style: styles[:rule], height: 4
    (1..3).each { |row| sheet.merge_cells("#{Axlsx.col_ref(first_index)}#{row}:#{last_col}#{row}") }
    sheet.add_row [], height: 10
    add_logo(sheet) if logo
  end

  def add_logo(sheet)
    return unless File.exist?(LOGO_PATH)

    sheet.add_image(image_src: LOGO_PATH.to_s, noSelect: true, noMove: true) do |image|
      image.width = 64
      image.height = 55
      image.start_at 0, 0
      image.anchor.from.colOff = 6 * 9525 # ~6px de respiro à esquerda (EMU)
    end
  end

  def last_column
    Axlsx.col_ref(COLUMNS.size - 1)
  end

  # ---- Auxiliares -------------------------------------------------------------

  def history?
    params[:scope] == 'history'
  end

  def now
    Time.current.in_time_zone(TIMEZONE)
  end

  def br_date(date)
    Date.parse(date.to_s).strftime('%d/%m/%Y')
  rescue ArgumentError
    date.to_s
  end
end
