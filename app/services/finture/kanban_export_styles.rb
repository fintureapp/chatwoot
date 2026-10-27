# Paleta e estilos de célula da exportação do Kanban (Finture::KanbanExportService),
# no mesmo padrão visual dos relatórios de Saúde: faixas pretas de seção, filete
# laranja, zebra bege e rótulos em negrito.
#
# Atenção: o caxlsx NÃO escapa aspas em format_code (gera XML inválido e o
# Excel "repara" o arquivo). Use só códigos sem aspas, ex.: [$R$-416].
class Finture::KanbanExportStyles
  FONT = 'Calibri'.freeze

  BLACK = '111111'.freeze
  ORANGE = 'EA622D'.freeze
  ORANGE_DARK = 'A9321B'.freeze
  GREEN_DARK = '1E7A46'.freeze
  BEIGE = 'F6F1EB'.freeze
  INK = '1F1A17'.freeze
  MUTED = '6B625C'.freeze
  LINE = 'E3DBD1'.freeze
  WHITE = 'FFFFFF'.freeze

  MONEY_FORMAT = '[$R$-416] #,##0.00'.freeze
  DATE_FORMAT = 'dd/mm/yyyy hh:mm'.freeze

  # Retorna um Hash nome => índice de estilo. Além dos estilos fixos (title,
  # subtitle, rule, section, header), cada chave de PAIRS existe em duas
  # versões: `nome` (fundo branco) e `nome_zebra` (fundo bege).
  def self.build(workbook)
    new(workbook).build
  end

  def initialize(workbook)
    @styles = workbook.styles
  end

  def build
    fixed.merge(zebra_pairs)
  end

  private

  attr_reader :styles

  def border
    { style: :thin, color: LINE }
  end

  def fixed
    {
      title: add(font_name: FONT, sz: 20, b: true, fg_color: INK, alignment: { vertical: :center }),
      subtitle: add(font_name: FONT, sz: 11, fg_color: MUTED, alignment: { vertical: :center }),
      rule: add(bg_color: ORANGE),
      section: add(font_name: FONT, sz: 11, b: true, fg_color: WHITE, bg_color: BLACK, border: border,
                   alignment: { vertical: :center, indent: 1 }),
      header: add(font_name: FONT, sz: 10, b: true, fg_color: WHITE, bg_color: BLACK, border: border,
                  alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    }
  end

  # Capa (label/valor) e tabela (por tipo de coluna).
  def pairs
    center = { horizontal: :center, vertical: :center }
    cover = { font_name: FONT, sz: 11, border: border, alignment: { horizontal: :left, vertical: :center, indent: 1 } }
    base = { font_name: FONT, sz: 10, fg_color: INK, border: border, alignment: { vertical: :center } }
    {
      label: cover.merge(b: true, fg_color: INK), value: cover.merge(fg_color: INK),
      strong: cover.merge(b: true, fg_color: INK), accent: cover.merge(fg_color: ORANGE_DARK),
      text: base, int: base.merge(alignment: center),
      date: base.merge(format_code: DATE_FORMAT, alignment: center),
      money: base.merge(format_code: MONEY_FORMAT),
      neutral: base.merge(fg_color: MUTED, alignment: center),
      won: base.merge(b: true, fg_color: GREEN_DARK, alignment: center),
      lost: base.merge(b: true, fg_color: ORANGE_DARK, alignment: center)
    }
  end

  def zebra_pairs
    pairs.each_with_object({}) do |(key, attrs), result|
      result[key] = add(attrs)
      result[:"#{key}_zebra"] = add(attrs.merge(bg_color: BEIGE))
    end
  end

  def add(attrs)
    styles.add_style(attrs)
  end
end
