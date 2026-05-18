module AiAgent
  module Api
    module V1
      module Accounts
        # User-facing CRUD for the Bea knowledge base. Replaces the previous
        # Captain::Document tab that was wired to a separate (legacy) storage
        # the chat agent never read from. Uploaded PDFs are queued through
        # AiAgent::IngestDocumentJob, which extracts text, chunks parent/child,
        # embeds via OpenAI, and stores in pgvector — exactly the source
        # AiAgent::Tools::SearchKnowledgeTool consults at chat time.
        #
        # JSON shape mirrors enterprise/app/views/api/v1/accounts/captain/documents
        # so the existing Vue page (Index.vue + DocumentForm.vue) can talk to
        # this endpoint with only a URL swap on the API client.
        class DocumentsController < ::Api::V1::Accounts::BaseController
          before_action :current_account
          before_action -> { check_authorization(::AiAgent::Document) }
          before_action :set_documents, except: [:create]
          before_action :set_document, only: [:show, :destroy]

          RESULTS_PER_PAGE = 25

          def index
            page = (params[:page] || 1).to_i
            scope = @documents
            @documents_count = scope.count
            paginated = scope.offset((page - 1) * RESULTS_PER_PAGE).limit(RESULTS_PER_PAGE)

            render json: {
              payload: paginated.map { |doc| serialize_document(doc) },
              meta: { total_count: @documents_count, page: page }
            }
          end

          def show
            render json: serialize_document(@document)
          end

          def create
            @document = ::AiAgent::Document.new(
              account: Current.account,
              name: resolved_name,
              source_type: resolved_source_type,
              external_link: document_params[:external_link]
            )
            @document.pdf_file.attach(document_params[:pdf_file]) if document_params[:pdf_file].present?

            if @document.save
              ::AiAgent::IngestDocumentJob.perform_later(@document.id)
              render json: serialize_document(@document), status: :created
            else
              render_could_not_create_error(@document.errors.full_messages.join(', '))
            end
          end

          def destroy
            @document.destroy!
            head :no_content
          end

          private

          def set_documents
            @documents = Current.account.documents_for_bea.order(created_at: :desc)
          end

          def set_document
            @document = @documents.find(params[:id])
          end

          def document_params
            params.require(:document).permit(:name, :external_link, :pdf_file, :assistant_id)
          end

          # If the user uploaded a PDF, default the name to the file's base name.
          # If they pasted a URL without a name, default to the URL itself.
          def resolved_name
            return document_params[:name] if document_params[:name].present?
            return document_params[:pdf_file].original_filename.sub(/\.pdf\z/i, '') if document_params[:pdf_file].present?

            document_params[:external_link]
          end

          def resolved_source_type
            return 'pdf' if document_params[:pdf_file].present?

            'url'
          end

          # Match the field names the frontend expects (see DocumentCard.vue:
          # name, external_link, assistant, created_at). `assistant` is nil
          # because Bea isn't bound to a specific Captain::Assistant — the
          # whole RAG belongs to the account.
          def serialize_document(doc)
            {
              id: doc.id,
              account_id: doc.account_id,
              name: doc.name,
              external_link: doc.external_link,
              status: doc.status,
              content: nil,
              content_type: doc.source_type,
              file_size: doc.pdf_file.attached? ? doc.pdf_file.byte_size : nil,
              display_url: doc.external_link,
              assistant: nil,
              created_at: doc.created_at.to_i,
              updated_at: doc.updated_at.to_i
            }
          end
        end
      end
    end
  end
end
