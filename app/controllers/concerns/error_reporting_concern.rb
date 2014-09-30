module ErrorReportingConcern
  def report_omniauth_error(e)
    params['omniauth_data'] = session[:omniauth].presence || request.env['omniauth.auth']
    report_error(e)
  end

  def report_error(e)
    logger.error(e)
  end
end
