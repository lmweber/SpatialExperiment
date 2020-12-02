#' @name imgData-methods
#' @title Methods for handling image-related data
#' @aliases loadImg unloadImg addImg removeImg
#' 
#' @description 
#' The set of functions described below is designed to handle 
#' the image-related data stored inside a \code{SpatialExperiment}'s 
#' \code{imgData} \code{int_metadata} field. These include 
#' \itemize{
#' \item{\code{imgGrob/Path/Url()}
#'   to access the \code{grob}, path and URL 
#'   associated with an image or set of images}
#' \item{\code{loadImg()} 
#'   to load an image from a path or URL as a \code{grob}}
#' \item{\code{unloadImg()} 
#'   to unload an image, i.e. to drop the \code{grob}
#'   while retaining the image's source path and/or URL}
#' \item{\code{add/removeImg()} 
#'   to add/remove an image entry to/from 
#'   the \code{imgData} \code{DataFrame}}
#' } 
#' 
#' @param x a \code{\link{SpatialExperiment}}
#' @param sample_id,image_id 
#'   character string, \code{TRUE} or \code{NULL} specifying sample/image 
#'   identifier(s); here, \code{TRUE} is equivalent to all samples/images 
#'   and \code{NULL} specifies the first available entry (see details)
#' @param imageSource 
#'   a character string specifying an image file name 
#'   (.png, .jpg or .tif) or URL to source the image from
#' @param scaleFactor 
#'   single numeric scale factor used to rescale spatial 
#'   coordinates according to the image's resolution
#' @param load logical; should the image(s) be loaded as a \code{grob}?
#'   if FALSE, will store the path/URL instead
#' 
#' @return 
#' \code{add/removeImg()} return a \code{\link{SpatialExperiment}} 
#' with modified \code{imgData}; specifically, they create/remove 
#' an image entry (row) in the \code{imgData} \code{DataFrame}.
#' 
#' \code{imgGrob/Path/Url()} access relevant data in the \code{SpatialImage}(s)
#' stored inside the \code{imgData}'s \code{data} field. 
#' Depending on whether or not multiple entries are excesses,
#' a character string or vector is returned by \code{imgPath/Url()},
#' and a single or list of \code{grob}(s) is returned by \code{imgGrob()}.
#'   
#' @examples
#' data(ve)
#' (df <- imgData(ve))
#' 
#' # 'SpatialImage' accessors
#' (si <- df$data[[1]])
#' imgGrob(si)
#' imgPath(si)
#' imgUrl(si)
#' 
#' # unload all images
#' ve <- unloadImg(ve, 
#'   sample_id = TRUE, 
#'   image_id = TRUE)
#' imgData(ve)$data
#' 
#' # reload all images
#' ve <- loadImg(ve, 
#'   sample_id = TRUE, 
#'   image_id = TRUE)
#' imgData(ve)$data
#' 
#' # remove an image
#' ve <- removeImg(ve, 
#'   sample_id = "section1", 
#'   image_id = "detected")
#' imgData(ve)
#' 
#' # add an image
#' url <- "https://i.redd.it/3pw5uah7xo041.jpg"
#' ve <- addImg(ve, 
#'   sample_id = "section1",
#'   image_id = "pomeranian",
#'   imageSource = url, 
#'   scaleFactor = NA_real_,
#'   load = TRUE)
#'   
#' grb <- imgGrob(ve, 
#'   sample_id = "section1", 
#'   image_id = "pomeranian")
#' grid::grid.draw(grb)
#'   
#' @author Helena L. Crowell

# getters ----------------------------------------------------------------------

#' @rdname imgData-methods
#' @export
setMethod("imgGrob", "SpatialExperiment", 
    function(x, sample_id=NULL, image_id=NULL) 
    {
        idx <- .get_img_idx(x, sample_id, image_id)
        si <- imgData(x)$data[idx]
        gs <- lapply(si, imgGrob)
        if (length(gs) > 1) 
            return(gs)
        gs[[1]]
    })

#' @rdname imgData-methods
#' @export
setMethod("imgPath", "SpatialExperiment", 
    function(x, sample_id=NULL, image_id=NULL) 
    {
        idx <- .get_img_idx(x, sample_id, image_id)
        si <- imgData(x)$data[idx]
        vapply(si, imgPath, character(1))
    })

#' @rdname imgData-methods
#' @export
setMethod("imgUrl", "SpatialExperiment", 
    function(x, sample_id=NULL, image_id=NULL) 
    {
        idx <- .get_img_idx(x, sample_id, image_id)
        si <- imgData(x)$data[idx]
        vapply(si, imgUrl, character(1))
    })

# loadImg ----------------------------------------------------------------------

#' @rdname imgData-methods
#' @importFrom grid rasterGrob
#' @importFrom BiocFileCache BiocFileCache
#' @importFrom magick image_read image_info
#' @export
setMethod("loadImg", "SpatialExperiment",
    function(x, sample_id=NULL, image_id=NULL) 
    { 
        # skip entries that are already loaded
        idx <- .get_img_idx(x, sample_id, image_id)
        sis <- imgData(x)$data[idx]
        idx <- idx[vapply(sis, function(.) 
            is.null(imgGrob(.)), logical(1))]
        
        # load images & update 'imgData'
        sis <- imgData(x)$data[idx]
        dfs <- lapply(sis, .load_img)
        df <- do.call(rbind, dfs)
        imgData(x)[idx, names(df)] <- df
        return(x)
    })

# unloadImg --------------------------------------------------------------------

#' @rdname imgData-methods
#' @export
setMethod("unloadImg", "SpatialExperiment",
    function(x, sample_id=NULL, image_id=NULL) 
    {
        idx <- .get_img_idx(x, sample_id, image_id)
        sis <- lapply(imgData(x)$data[idx], unloadImg)
        imgData(x)$data[idx] <- sis
        return(x)
    })

# addImg -----------------------------------------------------------------------

#' @rdname imgData-methods
#' @export
setMethod("addImg", "SpatialExperiment",
    function(x, imageSource, scaleFactor, sample_id, image_id, load=TRUE) 
    {
        # check validity of input arguments
        stopifnot(
            is.numeric(scaleFactor), 
            length(scaleFactor) == 1,
            
            is.character(sample_id), 
            length(sample_id) == 1, 
            sample_id %in% x$sample_id,
            
            is.character(image_id), 
            length(image_id) == 1,
            
            is.logical(load), 
            length(load) == 1)
        
        is_path <- tryCatch(
            error=function(e) e, 
            .path_validity(imageSource))
        
        is_url <- tryCatch(
            error=function(e) e, 
            .url_validity(imageSource))
        
        if (!(isTRUE(is_path) || isTRUE(is_url)))
            stop("Invalid 'imageSource'; should be an ",
                " image file name (.png or .jpg) or", 
                " URL to source the image from")
        
        # check that image entry doesn't already exist
        idx <- tryCatch(
            error=function(e) e,
            .get_img_idx(x, sample_id, image_id))
        if (!inherits(idx, "error"))
            stop("'imgData' already contains an entry with", 
                sprintf(
                    " 'image_id = %s' and 'sample_id = %s'", 
                    dQuote(image_id), dQuote(sample_id)))
        
        # get & add valid 'imgData' entry
        df <- .get_imgData(imageSource, scaleFactor, sample_id, image_id, load)
        imgData(x) <- rbind(imgData(x), df)
        return(x)
    })

# removeImg --------------------------------------------------------------------

#' @rdname imgData-methods
#' @export
setMethod("removeImg", "SpatialExperiment",
    function(x, sample_id=NULL, image_id=NULL) { 
        idx <- .get_img_idx(x, sample_id, image_id)
        imgData(x) <- imgData(x)[-idx, , drop=FALSE]
        return(x)
    })