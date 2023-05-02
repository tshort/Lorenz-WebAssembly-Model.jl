# do not remove this first line
using PkgPage

#
# Feel free to add whatever custom hfun_* or lx_*
# you might want to use in your site here
#


"""
hfun_rawoutput(params::Vector{String})

Include the raw file contents with no conversions
"""
function hfun_rawoutput(params::Vector{String})
    outpath  = Franklin.form_codepaths(params[1]).out_path
    # does output exist?
    isfile(outpath) || return html_err("`$(params[1])`: could not find the " *
                                       "relevant output file.")
    return read(outpath, String)
end