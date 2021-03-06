#' Convert between filenames and neuroglancer ids
#'
#' @description \code{swc2segmentid} converts an swc filename to a segment id
#'
#' @param x Input file or id
#' @param include.fragment Whether to include the sub identifier of the skeleton
#'   fragment (see details).
#' @return for \code{swc2segmentid} a numeric vector or matrix depending on the
#'   value of \code{include.fragment}
#' @export
#' @name fafbseg-ids
#' @importFrom stringr str_match
#' @examples
#' swc2segmentid("10001654273.1.swc")
#' swc2segmentid(sprintf("10001654273.%d.swc", 0:2), include.fragment=TRUE)
swc2segmentid <- function(x, include.fragment=FALSE) {
  res=str_match(basename(x), "^(\\d+)(\\.(\\d+)){0,1}\\.[Ss][Ww][Cc]$")
  if(isTRUE(include.fragment)) {
    res=res[,c(2,4), drop=FALSE]
    colnames(res)=c("segment", "fragment")
    res
  } else {
    res=res[,2]
  }
  mode(res)='numeric'
  res
}

#' @description \code{segmentid2zip} converts a segment id to the zip file that
#'   contains it
#' @export
#' @rdname fafbseg-ids
#' @examples
#' \donttest{
#' segmentid2zip(10001654273)
#' segmentid2zip(swc2segmentid("10001654273.1.swc"))
#' }
segmentid2zip <- function(x) {
  divisor <- find_zip_divisor(getOption("fafbseg.skelziproot"))
  sprintf("%d.zip", as.numeric(x) %/% divisor)
}

#' @description \code{zip2segmentstem} converts a zip file to the initial part
#'   of the segment id i.e. the segment stem (see details).
#'
#' @details Segment ids are unique integers. There are about 8E8 in the current
#'   skeletonisation but it seems that the ids can still be > 2^31 (usually
#'   \code{.Machine$integer.max}). Therefore they will be stored in R as numeric
#'   values or the \code{bit64::integer64} values.
#'
#'   Each segmentation has keen skeletonised however this usually results in
#'   multiple skeleton fragments which have been written out as separate SWC
#'   files: \code{"named <segment id>.<fragment>.swc"}
#'
#'   Each segment id is mapped onto a zip file by dividing by a divisor and
#'   discarding the remainder. Peter Li's data release of 2018-10-02 switched
#'   from 1E5 to 1E6.
#' @export
#' @rdname fafbseg-ids
#' @importFrom tools file_path_sans_ext
zip2segmentstem <- function(x) {
  as.integer(file_path_sans_ext(basename(x)))
}


#' Helper function to turn diverse inputs into neuroglancer segment ids
#'
#' @param x A neuroglancer scene specification form either in raw JSON format
#'   (character vector), the path to a file on disk, a neuroglancer scene URL
#'   (which embeds a JSON scene specification in a single URL), or an R list
#'   generated by parsing one of the above.
#' @param as_character Whether to return segments as character rather than
#'   numeric vector.
#' @param include_hidden Whether to include \code{hiddenSegments} (typically for
#'   flywire scenes).
#' @param ... Additional arguments passed to \code{\link{ngl_decode_scene}}
#'
#' @return Numeric (or character) vector of segment ids
#' @export
#' @examples
#' # no change
#' ngl_segments(c(10950626347, 10952282491, 13307888342))
#' # just turns these into numeric
#' ngl_segments(c("10950626347", "10952282491", "13307888342"))
#'
#' \donttest{
#' u="https://ngl.flywire.ai/?json_url=https://globalv1.flywire-daf.com/nglstate/5409525645443072"
#' ngl_segments(u, as_character = TRUE)
#' }
#'
#' \dontrun{
#' # from clipboard
#' ngl_segments(clipr::read_clip())
#'
#' # URL
#' ngl_segments("<ngl-scene-url>")
#' # path to file on disk
#' ngl_segments("/path/to/scene.json")
#' # R list
#' ngl_segments(scenelist)
#' }
ngl_segments <- function(x, as_character=FALSE, include_hidden=TRUE, ...) {
  if(is.numeric(x)) return(if(as_character) as.character(x) else as.numeric(x))

  if(is.character(x)) {
    nn <- suppressWarnings(as.numeric(x))
    # character vector of segment ids
    if(all(!is.na(nn))){
      return(if(as_character) as.character(x) else nn)
    } else {
      x=ngl_decode_scene(x, ...)
    }
  }

  layers=ngl_layers(x)
  if(is.null(layers))
    stop("Cannot find layers entry")

  sl = sapply(layers, function (y) {
    res = y[['segments']]
    if (include_hidden) union(res, y[['hiddenSegments']]) else res
  }, simplify = F)
  lsl=sapply(sl, length)
  nsegs=sum(lsl>0)
  if(nsegs==0)
    stop("Sorry. No segments entry in this list!")
  if(nsegs>1)
    stop("Sorry. More than one segments entry in this list:\n",
         paste(names(lsl)[lsl>0], collapse = '\n'))
  segments=unlist(sl[lsl>0])
  if(as_character) as.character(segments) else as.numeric(segments)
}

ngl_layers <- function(x) {
  if(is.character(x)) {
    if(length(x)==1 && grepl("^https{0,1}://", x)) {
      # looks like a URL
      x <- ngl_decode_scene(x)
    } else {
      if(length(x)==1 && file.exists(x)) {
        # looks like a file on disk
        x <- jsonlite::read_json(x, simplifyVector = TRUE)
      } else {
        x <- jsonlite::fromJSON(x, simplifyVector = TRUE)
      }
    }
  }
  if(!is.list(x))
    stop("Unable to extract segment information from list")

  x[['layers']]
}

null2na <- function(x) sapply(x, function(y) if(is.null(y)) NA else y,USE.NAMES = F)
ngl_segmentation <- function(x=getOption('fafbseg.sampleurl')) {
  layers=ngl_layers(x)
  sources=sapply(layers, "[[", "source")
  types=sapply(layers, "[[", "type")
  st = data.frame(
    source = null2na(sources),
    type = null2na(types),
    n = seq_along(layers),
    stringsAsFactors = F
  )
  # remove any layers without defined sources
  st=st[!is.na(st$source),,drop=FALSE]
  seglayer=grep('seg', st$type)
  if(length(seglayer)) layers[[seglayer[1]]] else NULL
}
