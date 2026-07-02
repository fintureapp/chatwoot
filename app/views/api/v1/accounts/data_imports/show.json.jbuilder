json.partial! 'api/v1/accounts/data_imports/data_import', formats: [:json], data_import: @data_import

import_errors_total_count = @import_errors_total_count || @data_import.import_errors.non_skip_logs.count
import_errors_per_page = @import_errors_per_page || Api::V1::Accounts::DataImportsController::IMPORT_ERRORS_PER_PAGE
import_errors_total_pages = @import_errors_total_pages || [(import_errors_total_count.to_f / import_errors_per_page).ceil, 1].max
import_errors_page = @import_errors_page || 1
paginated_import_errors = @data_import.import_errors.non_skip_logs
                                      .order(created_at: :desc)
                                      .offset((import_errors_page - 1) * import_errors_per_page)
                                      .limit(import_errors_per_page)
import_errors = @import_errors || paginated_import_errors
skip_logs_total_count = @skip_logs_total_count || @data_import.import_errors.skip_logs.count
skip_logs_per_page = @skip_logs_per_page || Api::V1::Accounts::DataImportsController::SKIP_LOGS_PER_PAGE
skip_logs_total_pages = @skip_logs_total_pages || [(skip_logs_total_count.to_f / skip_logs_per_page).ceil, 1].max
skip_logs_page = @skip_logs_page || 1
skip_logs_source_object_type = @skip_logs_source_object_type
skip_logs_counts_by_type = @skip_logs_counts_by_type || @data_import.import_errors.skip_logs.group(:source_object_type).count
skip_logs = @skip_logs || @data_import.import_errors.skip_logs
                                      .order(created_at: :desc)
                                      .offset((skip_logs_page - 1) * skip_logs_per_page)
                                      .limit(skip_logs_per_page)

json.import_errors do
  json.array! import_errors do |import_error|
    json.id import_error.id
    json.error_code import_error.error_code
    json.message import_error.message
    json.source_object_type import_error.source_object_type
    json.source_object_id import_error.source_object_id
    json.details import_error.details
    json.created_at import_error.created_at
  end
end

json.import_errors_pagination do
  json.current_page import_errors_page
  json.per_page import_errors_per_page
  json.total_count import_errors_total_count
  json.total_pages import_errors_total_pages
end

json.skip_logs do
  json.array! skip_logs do |skip_log|
    json.id skip_log.id
    json.kind skip_log.details['kind']
    json.error_code skip_log.error_code
    json.message skip_log.message
    json.source_object_type skip_log.source_object_type
    json.source_object_id skip_log.source_object_id
    json.details skip_log.details
    json.created_at skip_log.created_at
  end
end

json.skip_logs_pagination do
  json.current_page skip_logs_page
  json.per_page skip_logs_per_page
  json.total_count skip_logs_total_count
  json.total_pages skip_logs_total_pages
end

json.skip_logs_filters do
  json.selected_source_object_type skip_logs_source_object_type
  json.counts_by_type skip_logs_counts_by_type
end
