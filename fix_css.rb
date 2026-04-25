css = File.read('plugins/patients/frontend/routes/patients/patients-index.css')

css.gsub!(/rgb\(var\(--slate-1\)\)/, 'var(--color-bg-1)')
css.gsub!(/rgb\(var\(--slate-2\)\)/, 'var(--color-bg-2)')
css.gsub!(/rgb\(var\(--slate-3\)\)/, 'var(--color-bg-3)')
css.gsub!(/rgb\(var\(--slate-4\)\)/, 'var(--color-border-light)')
css.gsub!(/rgb\(var\(--slate-5\)\)/, 'var(--color-border)')
css.gsub!(/rgb\(var\(--slate-6\)\)/, 'var(--color-border)')
css.gsub!(/rgb\(var\(--slate-8\)\)/, 'var(--color-body)')
css.gsub!(/rgb\(var\(--slate-9\)\)/, 'var(--color-body)')
css.gsub!(/rgb\(var\(--slate-10\)\)/, 'var(--color-body)')
css.gsub!(/rgb\(var\(--slate-11\)\)/, 'var(--color-heading)')
css.gsub!(/rgb\(var\(--slate-12\)\)/, 'var(--color-heading)')

# Also fix body.dark overrides because they won't be needed if semantic vars are used!
# We can just remove the specific block or let it be if it was overridden cleanly, but wait, the variables inside the dark block were `rgb(var(--s-800))`.
css.gsub!(/rgb\(var\(--s-800\)\)/, 'var(--color-bg-2)')
css.gsub!(/rgb\(var\(--s-700\)\)/, 'var(--color-border-light)')
css.gsub!(/rgb\(var\(--s-200\)\)/, 'var(--color-heading)')

File.write('plugins/patients/frontend/routes/patients/patients-index.css', css)
