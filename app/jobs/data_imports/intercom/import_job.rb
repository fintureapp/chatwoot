class DataImports::Intercom::ImportJob < DataImports::Intercom::BaseJob
  def perform(data_import)
    return if skip_import?(data_import)

    importer = importer_for(data_import)
    importer.start!
    enqueue_next_stage(data_import, importer)
  rescue StandardError => e
    fail_unexpected_error(importer, e)
  end

  private

  def enqueue_next_stage(data_import, importer)
    if importer.import_contacts? && !importer.contacts_completed?
      DataImports::Intercom::ContactsPageJob.perform_later(data_import, importer.cursor_for('contacts'))
    elsif importer.import_conversations? && !importer.conversations_completed?
      DataImports::Intercom::ConversationsPageJob.perform_later(data_import, importer.cursor_for('conversations'))
    else
      importer.finish!
    end
  end
end
